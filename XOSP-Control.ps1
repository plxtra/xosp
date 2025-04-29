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

# "--project-directory", $TargetPath,
$ComposeArgs = @("compose", "--file", $(Join-Path $TargetPath "docker-compose.yml"), "--env-file", $(Join-Path $TargetPath $Parameters.DockerEnvFile)) #, "--progress", "quiet")

if ($Parameters.ForwardPorts)
{
	# Include port forwarding on non-linux hosts
	$ComposeArgs = @($ComposeArgs, "--file", $(Join-Path $TargetPath "docker-compose.ports.yml"))
}

$RunArgs = @("run", "-it", "--rm", "--quiet-pull")

& docker @ComposeArgs @RunArgs --entrypoint bash auth @args