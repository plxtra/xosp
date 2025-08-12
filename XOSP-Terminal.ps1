#Requires -PSEDition Core -Version 7

param(
	[Parameter(Position=0)]
	[string] $TargetService,
	[switch] $Root,
	[switch] $NoHeader,
	[int] $Index = -1,
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

# Check for a Docker installation
if ($null -eq (Get-Command docker -ErrorAction Ignore))
{
	Write-Host "Unable to locate Docker installation. Please ensure you have Docker Engine or Docker Desktop installed."

	exit
}

# Prepare our docker compose arguments
$ComposeArgs = @("compose", "--env-file", $(Join-Path $TargetPath $Parameters.DockerEnvFile))

foreach ($FileName in $Parameters.ComposeFiles)
{
	 $ComposeArgs += @("--file", $(Join-Path $TargetPath $FileName))
}

$ExecArgs = @("exec")

# Only has an effect on non-root containers
if ($Root)
{
	$ExecArgs += @("--user", "root")
}

# For replicated scenarios
if ($Index -gt 0)
{
	$ExecArgs += @("--index", $Index)
}

# If no parameters are supplied, default to starting the bash shell
if ($Arguments.Count -eq 0)
{
	$Arguments = @("bash")
}

if (-not $NoHeader)
{
	Write-Host "Container Terminal for $TargetService"
}

& docker @ComposeArgs @ExecArgs $TargetService @Arguments
