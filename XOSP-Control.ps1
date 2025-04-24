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

# "--project-directory", $TargetPath,
$ComposeArgs = @("compose", "--file", $(Join-Path $TargetPath "docker-compose.yml"), "--env-file", $(Join-Path $TargetPath $DockerEnvironmentFile)) #, "--progress", "quiet")

if ($Parameters.ForwardPorts)
{
	# Include port forwarding on non-linux hosts
	$ComposeArgs = @($ComposeArgs, "--file", $(Join-Path $TargetPath "docker-compose.ports.yml"))
}

$RunArgs = @("run", "-it", "--rm", "--quiet-pull")

& docker @ComposeArgs @RunArgs --entrypoint bash auth @args