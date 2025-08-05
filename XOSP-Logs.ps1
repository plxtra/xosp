#Requires -PSEDition Core -Version 7

$TargetPath = Join-Path $PSScriptRoot "Docker"
$ParamsSource = Join-Path $TargetPath "Init" "init-params.json"

if (!(Test-Path $ParamsSource))
{
	Write-Warning "Unable to find parameters. Did you run XOSP-Configure.ps1 first?"
	
	exit
}

# Execute our common sub-script. Dot sourcing to share the execution context and inherit any variables
. (Join-Path $PSScriptRoot "XOSP-Common.ps1") -UseCoreParams

#########################################

# Check for a Docker installation
if ($null -eq (Get-Command docker -ErrorAction Ignore))
{
	Write-Host "Unable to locate Docker installation. Please ensure you have Docker Engine or Docker Desktop installed."

	exit
}

if ($IsMacOS)
{
	Write-Warning "Logs are not accessible from the operating system on MacOS."
	Write-Host "Use XOSP-Control.ps1 and access the /root/.local/share/Paritech folder from within it."

	exit
}

$VolumeName = "$($Parameters.ComposeProject)_shared"

$VolumeStatus = & docker volume inspect --format json $VolumeName 2>$null | ConvertFrom-Json

if ($null -eq $VolumeStatus -or $VolumeStatus.Count -eq 0)
{
	Write-Warning "Unable to find shared volume. Did you run XOSP-Install.ps1?"

	exit
}

$VolumeInfo = $VolumeStatus[0]

if ($IsLinux)
{
	Write-Host "Logs are available at $($VolumeInfo.Mountpoint)"
}
elseif ($IsWindows)
{

	# Under Windows the logs are inside the docker VM, and there are several options for where depending on the docker version
	$RootPath = Join-Path "\\wsl$" "docker-desktop-data"

	if (-not (Test-Path $RootPath))
	{
		$RootPath = Join-Path "\\wsl$" "docker-desktop"
		
		if (-not (Test-Path $RootPath))
		{
			$SystemInfo = & docker system info --format json | ConvertFrom-Json

			Write-Warning "Unable to locate Docker WSL installation. Docker Version $($SystemInfo.ServerVersion)"
			
			exit
		}
	}

	# We found the WSL data, now work out where the volume data is. The most recent version uses this format
	$VolumePath = Join-Path $RootPath "mnt" "docker-desktop-disk" "data" "docker" "volumes" $VolumeName "_data"

	if (-not (Test-Path $VolumePath))
	{
		# Test some other options
		$VolumePath = Join-Path $RootPath "data" "docker" "volumes" $VolumeName "_data"

		if (-not (Test-Path $VolumePath))
		{
			$VolumePath = Join-Path $RootPath "version-pack-data" "community" "docker" "volumes" $VolumeName "_data"

			if (-not (Test-Path $VolumePath))
			{
				$SystemInfo = & docker system info --format json | ConvertFrom-Json

				Write-Warning "Unable to locate Docker volume folder. Docker version $($SystemInfo.ServerVersion)"
				
				exit
			}
		}
	}

	Write-Host "Logs are available at $VolumePath"
}
else
{
	Write-Warning "Unable to identify host platform"
}