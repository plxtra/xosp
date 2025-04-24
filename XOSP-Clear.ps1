#Requires -PSEDition Core -Version 7

if (!(Test-Path "XOSP-Params.ps1"))
{
	Write-Warning "Unable to find parameters. Ensure XOSP-Params.ps1 exists"
	
	exit
}

$RootPath = Get-Location
$SourcePath = Join-Path $RootPath Config # Where to find the configuration source files
$TargetPath = Join-Path $RootPath Docker # Where to output the prepared configurations

# Execute our various sub-scripts. Dot sourcing to share the execution context and inherit any variables
. (Join-Path $SourcePath "Init" "init-defaults.ps1")
. (Join-Path $PSScriptRoot "XOSP-Module.ps1")
. (Join-Path $PSScriptRoot "XOSP-Params.ps1")

# Apply any transformations we need
PostParameters

#########################################

$ComposeArgs = @("compose", "--file", $(Join-Path $TargetPath "docker-compose.yml"), "--env-file", $(Join-Path $TargetPath $DockerEnvironmentFile))
#$ComposeArgs += @("--progress", "quiet")

if ($Parameters.ForwardPorts)
{
	# Include port forwarding on non-linux hosts
	$ComposeArgs += @("--file", $(Join-Path $TargetPath "docker-compose.ports.yml"))
}

$Choices = "&Yes", "&No"

$Choice = $Host.UI.PromptForChoice("Clear XOSP Environment", "Clear all running containers, volumes, and logs?", $Choices, 1)

if ($Choice -eq 1)
{
	Write-Host "Aborted. No changes were made."
	
	exit
}

& docker @ComposeArgs down --volumes

Remove-Item -Path $Parameters.SharedDataPath -Recurse

Read-Host -Prompt "XOSP Environment cleared. Press Enter to finish"