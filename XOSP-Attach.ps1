#Requires -PSEDition Core -Version 7

param(
	[string] $TargetService,
	[switch] $NoHeader
)

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

if ([String]::IsNullOrEmpty($TargetService))
{

	$Choices = "&Cancel", "&Zenith"

	$Choice = $Host.UI.PromptForChoice("Attach XOSP Terminal", "Select the service to start with an interactive terminal.", $Choices, 0)

	switch ($Choice)
	{
		1 { $TargetService = "zenith" }
		default { exit }
	}
}

#########################################

# Prepare our docker compose arguments
$ComposeArgs = @("compose", "--env-file", $(Join-Path $TargetPath $Parameters.DockerEnvFile))
#$ComposeArgs += @("--progress", "quiet")

foreach ($FileName in $Parameters.ComposeFiles)
{
	 $ComposeArgs += @("--file", $(Join-Path $TargetPath $FileName))
}

# Ensure the service isn't running already
& docker @ComposeArgs stop $TargetService

$RunArgs = @("run", "-it", "--rm", "--quiet-pull")

if (-not $NoHeader)
{
	Write-Host "Service Terminal for the Plxtra XOSP distribution"
}

& docker @ComposeArgs @RunArgs $TargetService @args