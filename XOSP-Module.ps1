# This file contains shared code for XOSP operations, and is not meant to be executed directly

# Set some defaults, which may be changed by the params file
$DockerEnvironmentFile = ".env" # What to call the docker .env file

if ($IsWindows)
{
	$DockerHost = "windows"
	$Parameters.SharedDataPath = "${env:ProgramData}\XOSP"
	$Parameters.ForwardPorts = $true
	$Parameters.SslPort = 8043
}
elseif ($IsMacOS)
{
	$DockerHost = "osx"
	$Parameters.SharedDataPath = "/usr/share/Plxtra/XOSP"
	$Parameters.ForwardPorts = $true
	$Parameters.SslPort = 8043
}
else
{
	# Default to Linux if unrecognised (or if $IsLinux)
	$DockerHost = "linux"
	$Parameters.SharedDataPath = "/usr/share/Plxtra/XOSP"
}

$CurrentTimeZone = [TimeZoneInfo]::Local

if ($CurrentTimeZone.HasIanaId)
{
	$Parameters.MarketTimeZone = $CurrentTimeZone.Id;
}
else
{
	$IanaTimeZone = ""
	
	if ([TimeZoneInfo]::TryConvertWindowsIdToIanaId([TimeZoneInfo]::Local.Id, [ref] $IanaTimeZone))
	{
		$Parameters.MarketTimeZone = $IanaTimeZone;
	}	
}

function PostParameters()
{
	# Occurs after XOSP-Params, so we can use any values set there
	# Any variables that get set, use the $script: scope

	# If we're specifying an SSL port (the default) then we want to have a suffix value we can insert into config files
	if ($Parameters.SslPort -ne 443)
	{
		$Parameters.SslSuffix = ":" + $Parameters.SslPort
		
	}
	else
	{
		$Parameters.SslSuffix = ""
	}

	$Parameters.RootUri = $Parameters.RootDomainName + $Parameters.SslSuffix

	$MarketCode = $Parameters.MarketCode

	if ($null -eq $Parameters.MarketShortCode)
	{
		$Parameters.MarketShortCode = $MarketCode
	}


	$Parameters.MarketBoardCode = "$MarketCode::$MarketCode"
	$Parameters.MarketRouteCode = "$MarketCode::$MarketCode"
}

$Databases = @("Audit", "Foundry", "Prodigy", "OMS", "Sessions", "Herald", "Doppler", "Watchmaker", "Motif", "MarketHoliday", "Vault")

$SubDomains = @("arclight", "auth", "expo", "foundry", "iq", "motif", "svc", "ws")

function FailWithError([string] $Text)
{
	if ($global:LASTEXITCODE -lt 0)
	{
		Read-Host -Prompt "$Text ($global:LASTEXITCODE)"
		exit -1
	}
}