#Requires -PSEDition Core -Version 7

param(
	[switch] $AlwaysPull = $false, # True to always pull images from the repository
	[switch] $SkipInit = $false, # True to always skip initialisation, and just create the containers
	[switch] $Verbose = $false
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

$ComposeArgs = @("compose", "--env-file", $(Join-Path $TargetPath $Parameters.DockerEnvFile))

# If configured with LetsEncrypt, the .le.yml variant should already be included here
foreach ($FileName in $Parameters.ComposeFiles)
{
	 $ComposeArgs += @("--file", $(Join-Path $TargetPath $FileName))
}

$Extension.Renew($TargetPath, $Parameters, $ComposeArgs)
