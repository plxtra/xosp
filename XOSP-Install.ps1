#Requires -PSEDition Core -Version 7

param(
	[switch] $AlwaysPull = $false
)

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

# Check the Docker Engine is actually running
$DockerVersion = & docker version --format json 2>$null | ConvertFrom-Json

if ($null -eq $DockerVersion -or $null -eq $DockerVersion.Server)
{
	Write-Host "Could not connect to Docker Engine. Please ensure Docker Engine is started and running."

	exit
}

#########################################
# TODO: Remove this for release

if (!($Parameters.RegistryUri -match "(?<id>\d+)\.dkr\.ecr\.(?<region>[\w-]+)\.amazonaws\.com"))
{
	Write-Warning "Invalid Amazon ECR registry URL. Must match <Registry ID>.dkr.ecr.<AWS Region>.amazonaws.com"
	
	exit
}

$AwsRegion = $Matches.region

$LoginOutput = & aws ecr get-login-password --region $AwsRegion | docker login --username AWS --password-stdin $Parameters.RegistryUri

if (!$?)
{
	Write-Warning "Failed to login to AWS container registry"
	Write-Host $LoginOutput
	exit
}

#########################################

# "--project-directory", $TargetPath,
$ComposeArgs = @("compose", "--file", $(Join-Path $TargetPath "docker-compose.yml"), "--env-file", $(Join-Path $TargetPath $DockerEnvironmentFile))
#$ComposeArgs += @("--progress", "quiet")

if ($Parameters.ForwardPorts)
{
	# Include port forwarding on non-linux hosts
	$ComposeArgs += @("--file", $(Join-Path $TargetPath "docker-compose.ports.yml"))
}

$UpArgs = @("up", "--no-recreate", "--wait")
$RunArgs = @("run", "--rm", "--quiet-pull")
$InitArgs = @($RunArgs, "--volume", ((Join-Path $TargetPath "Init") + ":/init"))

#########################################

# Pre-create all our containers at once. We'll bring them up once their dependencies are configured
$CreateArgs = @("create")

if ($AlwaysPull)
{
	$CreateArgs += @("--pull", "always")
}

Write-Host "Initialising Docker Containers..."
& docker @ComposeArgs @CreateArgs
FailWithError "Unable to create the XOSP containers."

# Does our Postgres DB have any content yet?
$UsageData = & docker system df --verbose --format json | ConvertFrom-Json
$PgDataVolumeName = $Parameters.ComposeProject + "_pgdata"
$PgDataVolume = $UsageData.Volumes | Where-Object { $_.Name -eq $PgDataVolumeName }

# Start our support services like Postgres and Redis
if ($null -eq $PgDataVolume -or $PgDataVolume.Size -eq "0B")
{
	Write-Host "Starting Support services and initialising database, this may take a few moments..."
}
else
{
	# If we already have data inside our pgdata volume, we probably won't be running database initialisation
	Write-Host "Starting Support services..."
}

& docker @ComposeArgs @UpArgs postgres redis auth
FailWithError "Unable to bring up all support services."

#TODO: Remove the initialisation volume from postgres?

#########################################

# Exercise the REST API to populate client ids
# First time we run the control tool, we force a rebuild, since docker won't do it automatically even if the dockerfile changes
& docker @ComposeArgs @InitArgs --build control "/init/auth-init.ps1"
FailWithError "Unable to initialise the Auth Server database."

#########################################

Write-Host "Starting Core Application services..."
# Start all core application services that don't directly connect to anything besides the Auth Server and Support services
& docker @ComposeArgs @UpArgs audit foundry.hub foundry.proc oms.hub prodigy.archiver prodigy.gateway prodigy.internal prodigy.monitor prodigy.public prodigy.worker sessions vault
FailWithError "Unable to bring up all core containers."

# TODO: Exercise the REST API to populate the FIX sessions
#& docker @ComposeArgs @SetupArgs control "/init/fix-init.ps1" -Owner $Parameters.MarketOperator -OwnerName $Parameters.MarketOperatorName

# REST API is currently incomplete, so we insert the required sessions directly into the database
Write-Host "Initialising FIX Sessions..."
& docker @ComposeArgs exec postgres psql -U $Parameters.DbSuperUser --quiet -f '/docker-entrypoint-initdb.d/Init/fix-init.sql' ("Prodigy" + $Parameters.DatabaseSuffix)
FailWithError "Unable to initialise the FIX Sessions."

Write-Host "Initialising Core Applications..."
& docker @ComposeArgs @InitArgs control -command "/init/core-init.ps1"
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

Write-Host "Preparing Networking..."

# Retrieve the nginx container details
$ContainerList = & docker @ComposeArgs ps --format json --no-trunc nginx | ConvertFrom-Json

if ($null -eq $ContainerList)
{
	Write-Warning "Unable to locate Nginx container, networking may not function"
}
else
{	
	$NginxID = $ContainerList[0].ID
	
	# Retrieve the container IP address
	$NginxDetails = & docker inspect --format json $NginxID | ConvertFrom-Json
	
	if ($Parameters.ForwardPorts)
	{
		# On Windows/MacOS we can't connect to the docker container directly, and have to bind a local port
		# so forwarding ports is the default (via the docker-compose.ports.yml file)
		$ContainerIP = "127.0.0.1"
	}
	else
	{
		# On Linux we can connect to the container directly (without port binding), so unless ports are forwarded, we need to be part of the bridge network to be visible
		if ("bridge" -notin $NginxDetails.NetworkSettings.Networks.PSObject.Properties.name)
		{
			# Not attached to the bridge network, so make it visible
			& docker network connect bridge $NginxID
			$NginxDetails = & docker inspect --format json $NginxID | ConvertFrom-Json
		}
		
		$NetworkName = "bridge" # $Parameters.ComposeProject + "_default";
		$ContainerIP = $NginxDetails.NetworkSettings.Networks.($NetworkName).IPAddress
	}	
	
	$TargetFile = Join-Path $TargetPath "hosts"

	$SourceContent = New-Object System.Text.StringBuilder
	$RootDomainName = $Parameters.RootDomainName
	
	foreach ($Record in $SubDomains.GetEnumerator() | Sort-Object)
	{
		$SourceContent.AppendLine("$ContainerIP $Record.$RootDomainName") > $null
	}
	
	Set-Content $TargetFile -Value $SourceContent.ToString() > $null
}

$RootUri = $Parameters.RootUri

Write-Host "================================================================================"

Write-Host "Configuration complete. The next steps require some manual work:"
Write-Host " 1. For DNS resolution, copy the 'hosts' file to your platform-specific hosts file."
Write-Host "    $(Join-Path $TargetPath `"hosts`")"
Write-Host " 2. For HTTPS, install the appropriate certificate file into your browser certificate store."
Write-Host "    $(Join-Path $TargetPath $Parameters.CertificateFile).crt"
Write-Host "DNS and HTTPS are necessary before you can install or access the platform, as they are required for OAuth login."
Write-Host "================================================================================"
Write-Host "Once complete, the system can be accessed with the login '$($Parameters.AdminUser)' and password '$($Parameters.AdminPassword)'"
Write-Host "- Trading Terminal: https://motif.${RootUri}/"
Write-Host "                    https://arclight.${RootUri}/"
Write-Host "                    https://expo.${RootUri}/"
Write-Host "- Registry for cash and holdings management: https://foundry.${RootUri}/"
Write-Host "- User Account management: https://auth.${RootUri}/"
Write-Host "================================================================================"