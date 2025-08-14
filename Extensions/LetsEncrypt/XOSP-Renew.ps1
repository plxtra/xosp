#Requires -PSEDition Core -Version 7

param(
	[Parameter(Position=0)]
	[string] $Action = $null
)

$TargetPath = Join-Path $PSScriptRoot "Docker"
$ExtensionPath = Join-Path $PSScriptRoot "Extensions" # Where to find any extensions
$ParamsSource = Join-Path $TargetPath "Init" "init-params.json"

if (!(Test-Path $ParamsSource))
{
	Write-Warning "Unable to find parameters. Did you run XOSP-Configure.ps1 first?"
	
	exit
}

# Execute our common sub-script. Dot sourcing to share the execution context and inherit any variables
. (Join-Path $PSScriptRoot "XOSP-Common.ps1") -UseCoreParams

#########################################

if ($null -eq $Parameters.Extensions -or $Parameters.Extensions.Count -eq 0)
{
	Write-Warning "LetsEncrypt extension not installed. Run XOSP-Configure.ps1 LetsEncrypt"
	
	exit
}

# Load the LetsEncrypt extension by itself
$ExtensionFile = Join-Path $ExtensionPath "LetsEncrypt.ps1"

$Factory = & $ExtensionFile
$Extension = $null

foreach ($Settings in $Parameters.Extensions.GetEnumerator())
{
	if ($Settings.Name -eq $Factory.Name)
	{
		$Extension = $Factory.Create($Settings)

		break
	}
}

if ($null -eq $Extension)
{
	Write-Warning "LetsEncrypt extension not installed. Run XOSP-Configure.ps1 LetsEncrypt"
	
	exit
}

# Check the Docker Engine is running and contactable
$DockerVersion = & docker version --format json 2>$null | ConvertFrom-Json

if ($null -eq $DockerVersion -or $null -eq $DockerVersion.Server)
{
	Write-Host "Could not connect to Docker Engine. Please ensure Docker Engine is started and running."

	exit
}

#########################################

if ([String]::IsNullOrEmpty($Action))
{
	# Default action, trigger the renewal with certbot inside docker
	$ComposeArgs = @("compose", "--env-file", $(Join-Path $TargetPath $Parameters.DockerEnvFile))

	# If configured with LetsEncrypt, the .le.yml variant should already be included here
	foreach ($FileName in $Parameters.ComposeFiles)
	{
		$ComposeArgs += @("--file", $(Join-Path $TargetPath $FileName))
	}

	$Extension.Renew($TargetPath, $Parameters, $ComposeArgs)
}
else
{
	function Copy-WithReplace
	{
		[CmdletBinding()]
		param (
			[String] $SourcePath,
			[String] $TargetPath,
			[PSObject] $Replacements
		)
		
		$SourceContent = New-Object System.Text.StringBuilder(Get-Content $SourcePath -Raw)
			
		foreach ($KeyValue in $Replacements.GetEnumerator())
		{
			$SearchValue = '${' + $KeyValue.Key + '}'
			
			$SourceContent.Replace($SearchValue, $KeyValue.Value) > $null
		}
		
		$NewContent = $SourceContent.ToString()
		
		try
		{
			Set-Content -Path $TargetPath -Value $NewContent > $null
		}
		catch
		{
			# If running while an environment is already active, Docker can hold the file open and cause Set-Content to fail
			# We can delete the file and try again, and that will usually fix the problem
			Remove-Item $TargetPath
			
			Set-Content -Path $TargetPath -Value $NewContent -Force > $null
		}
	}

	switch ($Action.ToLowerInvariant())
	{
		"install" {
			if ($IsLinux)
			{
				if ($null -eq (Get-Command systemctl -ErrorAction Ignore))
				{
					Write-Host "XOSP Renewal auto-install only supports systemd"
					
					exit
				}

				$SystemdPath = Join-Path $HOME '.config' 'systemd' 'user'

				if (-not (Test-Path $SystemdPath))
				{
					New-Item -Path $SystemdPath -ItemType Directory > $null
				}

				$RenewParams = @{InstallPath=$PSScriptRoot; PwshPath=(Get-Command pwsh).Source}

				Copy-WithReplace -SourcePath (Join-Path $ExtensionPath "LetsEncrypt" "xosp-renew.service") -TargetPath (Join-Path $SystemdPath "xosp-renew.service") -Replacements $RenewParams
				Copy-WithReplace -SourcePath (Join-Path $ExtensionPath "LetsEncrypt" "xosp-renew.timer") -TargetPath (Join-Path $SystemdPath "xosp-renew.timer") -Replacements $RenewParams

				& systemctl --user daemon-reload
				& systemctl --user enable xosp-renew.timer
				& systemctl --user start xosp-renew.timer
			}
			elseif ($IsWindows)
			{
				# The script is tagged to require Powershell 7, which should always use pwsh.exe
				$Action = New-ScheduledTaskAction -Execute (Join-Path $PSHome "pwsh.exe") -WorkingDirectory $PSScriptRoot -Argument ".\XOSP-Renew.ps1"
				$Trigger = New-ScheduledTaskTrigger -Daily -DaysInterval 90 -At 12pm
				$Settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -DontStopIfGoingOnBatteries

				Register-ScheduledTask -TaskName "XOSP LetsEncrypt Renewal" -Action $Action -Trigger $Trigger -User $env:USERNAME
			}
			else
			{
				Write-Host "XOSP Renewal auto-install does not support your operating system"
				
				exit
			}
		}
		"uninstall" {
			if ($IsLinux)
			{
				if ($null -eq (Get-Command systemctl -ErrorAction Ignore))
				{
					Write-Host "XOSP Renewal auto-uninstall only supports systemd"
					
					exit
				}

				$SystemdPath = Join-Path $HOME '.config' 'systemd' 'user'
				$TimerPath = Join-Path $SystemdPath "xosp-renew.timer"

				if (-not (Test-Path $TimerPath))
				{
					Write-Host "No systemd renewal timer could be found"

					exit
				}

				& systemctl --user stop xosp-renew.timer
				& systemctl --user disable xosp-renew.timer

				Remove-Item (Join-Path $SystemdPath "xosp-renew.service")
				Remove-Item $TimerPath

				& systemctl --user daemon-reload

				# TODO: Clean up ~/.config/systemd/user if it's empty?
			}
			elseif ($IsWindows)
			{
				$Task = Get-ScheduledTask -TaskName "XOSP LetsEncrypt Renewal"

				if ($null -eq $Task)
				{
					Write-Host "No Scheduled Task could be found"
					
					exit
				}

				Unregister-ScheduledTask -InputObject $Task
			}
			else
			{
				Write-Host "XOSP Renewal auto-uninstall does not support your operating system"
				
				exit
			}
		}
	}	
}