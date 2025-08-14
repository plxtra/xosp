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

# Check the Docker Engine is running and contactable
$DockerVersion = & docker version --format json 2>$null | ConvertFrom-Json

if ($null -eq $DockerVersion -or $null -eq $DockerVersion.Server)
{
	Write-Host "Could not connect to Docker Engine. Please ensure Docker Engine is started and running."

	exit
}

$ExpectPullThrottling = $false

# Special handling to login with AWS Public/Private registries
if ($Parameters.RegistryUri -match "(?<id>\d+)\.dkr\.ecr\.(?<region>[\w-]+)\.amazonaws\.com")
{
	# If we're using a private AWS registry, we need to login
	$AwsRegion = $Matches.region

	$LoginOutput = & aws ecr get-login-password --region $AwsRegion | docker login --username AWS --password-stdin $Parameters.RegistryUri

	if (!$?)
	{
		Write-Warning "Failed to login to AWS private container registry"
		Write-Host $LoginOutput
		exit
	}
}
elseif ($Parameters.RegistryUri -match "public.ecr.aws/(?<id>\w+)")
{
	# If we're using the public AWS registry, there's a 1 pull-per-second throttling limit for unauthenticated users which we can easily hit
	if ($null -ne (Get-Command aws -ErrorAction Ignore))
	{
		# The CLI tools are installed, let's try to login, since the throttling is much less severe
		$LoginOutput = & aws ecr-public get-login-password --region us-east-1 | docker login --username AWS --password-stdin $Parameters.RegistryUri

		if (!$?)
		{
			Write-Warning "Failed to login to AWS public container registry, will continue unauthenticated"
			
			$ExpectPullThrottling = $true
		}
	}
	else
	{
		# AWS CLI is not installed, so we assume they're not logged in
		$ExpectPullThrottling = $true
	}
}

$Extensions = @()

if ($null -ne $Parameters.Extensions -and $Parameters.Extensions.Count -gt 0 -and (Test-Path $ExtensionPath))
{
	Write-Host "Loading Extensions..."

	$ExtensionFactories = @{}

	# Detect and create the extension factories
	foreach ($ExtensionFile in (Get-ChildItem (Join-Path $ExtensionPath "*") -File -Include @("*.ps1") | Foreach-Object { $_.FullName }))
	{
		$Factory = & $ExtensionFile

		$ExtensionFactories[$Factory.Name] = $Factory
	}

	# Instantiate each extension by name
	foreach ($Settings in $Parameters.Extensions.GetEnumerator())
	{
		$Factory = $ExtensionFactories[$Settings.Name]

		if ($null -eq $Factory)
		{
			Write-Host "Extension $($Settings.Name) does not exist"

			exit
		}

		$Extensions += $Factory.Create($Settings)
	}
}

#########################################

# Prepare our docker compose arguments
$ComposeArgs = @("compose", "--env-file", $(Join-Path $TargetPath $Parameters.DockerEnvFile))

if (-not $Verbose)
{
	$ComposeArgs += @("--progress", "quiet")
}

foreach ($FileName in $Parameters.ComposeFiles)
{
	 $ComposeArgs += @("--file", $(Join-Path $TargetPath $FileName))
}

$UpArgs = @("up", "--no-recreate", "--wait")

# Pre-create all our containers at once. We'll bring them up once their dependencies are configured
$CreateArgs = @("create", "--remove-orphans")

if ($AlwaysPull -and -not $ExpectPullThrottling)
{
	# We don't expect throttling, so we can just pull as part of create and do it all in parallel
	$CreateArgs += @("--pull", "always")
}

# Some registries have throttling applied to pull requests, so we disable parallelism and preload the images
if ($AlwaysPull -and $ExpectPullThrottling)
{
	& docker @ComposeArgs --parallel 1 pull --policy always
	FailWithError "Unable to pull the XOSP images."
}

#########################################

$UpgradePath = Join-Path $TargetPath "Init" "upgrade-required"

if (Test-Path $UpgradePath)
{
	if ($SkipInit)
	{
		Write-Warning "-SkipInit is invalid, upgrade is required"

		exit -1
	}

	$UpgradeVersion = Get-Content -Raw $UpgradePath
	Write-Host "Upgrading Installation from $UpgradeVersion to $($Parameters.Version)..."

	# Stop any running containers before performing the upgrade procedure
	& docker @ComposeArgs stop

	$Processors = @()
	$CurrentVersion = $UpgradeVersion

	while ($CurrentVersion -ne $Parameters.Version)
	{
		$UpgradeScriptPath = Join-Path $PSScriptRoot "Upgrades" "upgrade-$CurrentVersion.ps1"

		if (!(Test-Path $UpgradeScriptPath))
		{
			Write-Warning "No upgrade route exists from version $CurrentVersion"

			exit -1
		}

		$Processor = & $UpgradeScriptPath

		$Processors += $Processor

		$CurrentVersion = $Processor.TargetVersion
	}

	#########################################

	foreach ($Processor in $Processors)
	{
		Write-Host "`tUpgrading to $($Processor.TargetVersion)"
		
		$Processor.Upgrade($TargetPath, $Parameters, $ComposeArgs)
		
		# Ensure if we fail/abort here, we can resume later from the correct version
		$Processor.TargetVersion | Set-Content $UpgradePath -NoNewLine
	}

	Write-Host "`tUpgrade complete, continuing installation"

	Remove-Item $UpgradePath
}

if ($SkipInit)
{
	$UpArgs = @("up", "--wait")

	if ($AlwaysPull -and -not $ExpectPullThrottling)
	{
		# We don't expect throttling, so we can just pull as part of create and do it all in parallel
		$UpArgs += @("--pull", "always")
	}

	Write-Host "Initialising Docker Containers from $($Parameters.RegistryUri)..."
	
	& docker @ComposeArgs @UpArgs

	Write-Host "Installation complete, skipping environment initialisation."

	exit
}

#########################################

Write-Host "Initialising environment..."

# First time we run the control tool, we force a rebuild, since docker won't do it automatically even if the dockerfile changes
# Create a persistent container for initialisation, which we can quickly invoke commands inside
& docker @ComposeArgs up --quiet-pull --build --detach control-init
#$ControlContainer = "$($Parameters.ComposeProject)-control-init-1"

Write-Host "`tShared Volume permissions..."
# Grant permission on the shared folder to all users, so both root and non-root containers can both create their folders
# Make sure we set the permissions on both possible mounting locations
& docker @ComposeArgs exec control-init bash -c "chmod a+rw /root/.local/share/Paritech /usr/share/Paritech"

# Pre-installation for any extensions
foreach ($Extension in $Extensions)
{
	if ($null -ne ($Extension | Get-Member PreInstall))
	{
		$Extension.PreInstall($TargetPath, $Parameters, $ComposeArgs)
	}
}

#########################################

Write-Host "Initialising Docker Containers from $($Parameters.RegistryUri)..."

& docker @ComposeArgs @CreateArgs
FailWithError "Unable to create the XOSP containers."

#########################################

Write-Host "Starting Support services..."

& docker @ComposeArgs @UpArgs postgres redis auth
FailWithError "Unable to bring up all support services."
#TODO: Remove the initialisation mount binding from postgres?

#########################################

# Exercise the REST API to populate client ids
#& docker exec $ControlContainer pwsh "/init/auth-init.ps1" -UserName $Parameters.AdminUser -Password $Parameters.AdminPassword
& docker @ComposeArgs exec control-init pwsh -Command "/init/auth-init.ps1" -UserName $Parameters.AdminUser -Password $Parameters.AdminPassword
FailWithError "Unable to initialise the Auth Server database."

Write-Host "Starting Core Application services..."
# Start all core application services that don't directly connect to anything besides the Auth Server and Support services
& docker @ComposeArgs @UpArgs audit authority foundry.hub foundry.proc oms.hub prodigy.archiver prodigy.gateway prodigy.internal prodigy.monitor prodigy.public prodigy.worker sessions
FailWithError "Unable to bring up all core containers."

# REST API is currently incomplete, so we insert the required sessions directly into the database
Write-Host "Initialising FIX Sessions..."
& docker @ComposeArgs exec postgres psql -U $Parameters.DbSuperUser --quiet -f '/docker-entrypoint-initdb.d/Init/fix-init.sql' ("Prodigy" + $Parameters.DatabaseSuffix)
FailWithError "Unable to initialise the FIX Sessions."

Write-Host "Initialising Core Applications..."
& docker @ComposeArgs exec control-init pwsh -Command "/init/core-init.ps1"
FailWithError "Unable to initialise the Core Applications."

#########################################

# Start remaining services that depend on others (and need the core services to be configured first)
Write-Host "Starting Secondary Application Services..."
& docker @ComposeArgs @UpArgs oms.prodigy foundry.admin foundry.oms foundry.prodigy watchmaker
FailWithError "Unable to bring up all secondary containers."

#########################################

# Start API and front-end services, and Nginx as reverse proxy
Write-Host "Starting Frontend Services..."
& docker @ComposeArgs @UpArgs arclight expo motif.services motif.web nginx zenith
FailWithError "Unable to bring up Frontend Services."

#########################################

# Docker configuration complete

#########################################

Write-Host "Finalising installation..."

if ($Parameters.RootDomainName.EndsWith("localhost"))
{

	$ContainerIP = "127.0.0.1"
	
	$TargetFile = Join-Path $TargetPath "hosts"

	$SourceContent = New-Object System.Text.StringBuilder
	$RootDomainName = $Parameters.RootDomainName
	
	foreach ($Record in $Parameters.SubDomains.GetEnumerator() | Sort-Object)
	{
		$SourceContent.AppendLine("$ContainerIP $Record.$RootDomainName") > $null
	}
	
	Set-Content $TargetFile -Value $SourceContent.ToString() > $null
}

# Post-Installation for extensions
foreach ($Extension in $Extensions)
{
	if ($null -ne ($Extension | Get-Member PostInstall))
	{
		$Extension.PostInstall($TargetPath, $Parameters)
	}
}

& docker @ComposeArgs down control-init

#########################################

$HttpsUri = $Parameters.HttpsUri

if ($Parameters.RootDomainName.EndsWith("localhost"))
{
	Write-Host "================================================================================"
	Write-Host "MANUAL STEP REQUIRED:"
	Write-Host "  A 'hosts' file has been generated for $($Parameters.RootDomainName) at:"
	Write-Host "    $(Join-Path $TargetPath `"hosts`")"
	Write-Host "  Copy the contents of this 'hosts' file to your platform-specific hosts file to enable DNS resolution."
}

if ($Parameters.GenerateCertificate)
{
	Write-Host "================================================================================"
	Write-Host "MANUAL STEP REQUIRED:"
	Write-Host "  A self-signed certificate has been generated at:"
	Write-Host "    $(Join-Path $TargetPath $Parameters.CertificateFile).crt"
	Write-Host "  Install this certificate file into your system or browser certificate store to enable HTTPS."
}

Write-Host "================================================================================"
Write-Host "Installation complete. There may be further manual steps required - see above."
Write-Host "Once completed, the system can be accessed with the login '$($Parameters.AdminUser)' and password '$($Parameters.AdminPassword)'"
Write-Host "- Trading Terminal: https://motif.${HttpsUri}/"
Write-Host "                    https://arclight.${HttpsUri}/"
Write-Host "                    https://expo.${HttpsUri}/"
Write-Host "- Registry for cash and holdings management: https://foundry.${HttpsUri}/"
Write-Host "- User Account management: https://auth.${HttpsUri}/Identity/Account/Manage"
Write-Host "Environment logs and temporary databases will be stored at $($Parameters.SharedDataPath)"
Write-Host "================================================================================"
