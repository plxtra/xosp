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

$ComposeArgs = @("compose", "--file", $(Join-Path $TargetPath "docker-compose.yml"), "--env-file", $(Join-Path $TargetPath $Parameters.DockerEnvFile))
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

if (Test-Path $Parameters.SharedDataPath)
{
	Remove-Item -Path $Parameters.SharedDataPath -Recurse
}

Read-Host -Prompt "XOSP Environment cleared. Press Enter to finish"