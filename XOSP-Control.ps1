#Requires -PSEDition Core -Version 7

param(
	[Parameter(Position=0)]
	[string] $TargetService,
	[switch] $NoHeader,
	[Parameter(ValueFromRemainingArguments=$true)]
	[Alias("Args")]
	[string[]] $Arguments
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

# Check for a Docker installation
if ($null -eq (Get-Command docker -ErrorAction Ignore))
{
	Write-Host "Unable to locate Docker installation. Please ensure you have Docker Engine or Docker Desktop installed."

	exit
}

# Prepare our docker compose arguments
$ComposeArgs = @("compose", "--env-file", $(Join-Path $TargetPath $Parameters.DockerEnvFile))

#$ComposeArgs += @("--progress", "quiet")

foreach ($FileName in $Parameters.ComposeFiles)
{
	 $ComposeArgs += @("--file", $(Join-Path $TargetPath $FileName))
}

$RunArgs = @("run", "-it", "--rm", "--quiet-pull")

if ([String]::IsNullOrEmpty($TargetService))
{
	if (-not $NoHeader)
	{
		Write-Host "Control Terminal for the Plxtra XOSP distribution"
	}

	& docker @ComposeArgs @RunArgs control @Arguments
}
else
{
	& docker @ComposeArgs @RunArgs --entrypoint bash $TargetService @Arguments
}