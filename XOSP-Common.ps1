# This file contains shared code for XOSP operations, and is not meant to be executed directly
param(
	[Alias("Profile")]
	[string] $ConfigProfile,
	[switch] $UseCoreParams
)

#########################################

if ($UseCoreParams)
{
	$private:ParamSource = (Join-Path $PSScriptRoot "Docker" "Init" "init-params.json")

	$Parameters = Get-Content $private:ParamSource -Raw | ConvertFrom-Json -AsHashtable
}
else
{
	# Set some defaults, which may be changed by the params file
	$private:ParamSources = @(
		(Join-Path $PSScriptRoot "Config" "Init" "init-defaults.json"),
		#(Join-Path $PSScriptRoot "Profiles" "$ConfigProfile.json"), # We could theoretically apply the profile, and then the users overrides
		(Join-Path $PSScriptRoot "XOSP-Params.json")
	)

	#########################################

	$private:Defaults = @{
		SharedDataPath = "~/Plxtra/XOSP"
		ForwardPorts = $false;
		SslPort = 443;
		MarketTimeZone = "Utc"
	}

	# Setup some host-specific defaults
	if ($IsWindows)
	{
		$private:Defaults.SharedDataPath = "${env:LOCALAPPDATA}\Plxtra\XOSP"
		$private:Defaults.ForwardPorts = $true
		$private:Defaults.SslPort = 8043
	}
	elseif ($IsMacOS)
	{
		$private:Defaults.SharedDataPath = "~/Plxtra/XOSP"
		$private:Defaults.ForwardPorts = $true
		$private:Defaults.SslPort = 8043
	}

	$CurrentTimeZone = [TimeZoneInfo]::Local

	if ($CurrentTimeZone.HasIanaId)
	{
		$private:Defaults.MarketTimeZone = $CurrentTimeZone.Id;
	}
	else
	{
		$IanaTimeZone = ""
		
		if ([TimeZoneInfo]::TryConvertWindowsIdToIanaId([TimeZoneInfo]::Local.Id, [ref] $IanaTimeZone))
		{
			$private:Defaults.MarketTimeZone = $IanaTimeZone;
		}	
	}

	#########################################

	$Parameters = @{}

	# Read in and override any parameters
	foreach ($SourceParamPath in $private:ParamSources.GetEnumerator())
	{
		$SourceParams = Get-Content -Raw $SourceParamPath | ConvertFrom-Json -AsHashtable

		foreach ($Pair in $SourceParams.GetEnumerator())
		{
			$Parameters[$Pair.Key] = $Pair.Value
		}
	}

	# Anything null or not set receives a default
	foreach ($Pair in $private:Defaults.GetEnumerator())
	{
		if ($Parameters.ContainsKey($Pair.Key))
		{
			if ($null -ne $Parameters[$Pair.Key])
			{
				continue
			}
		}

		$Parameters[$Pair.Key] = $Pair.Value
	}

	#########################################

	# Some parameters need to get generated based on the final configuration

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

#########################################

# Create a few arrays that get referenced in multiple places
$Databases = @("Audit", "Foundry", "Prodigy", "OMS", "Sessions", "Herald", "Doppler", "Watchmaker", "Motif", "MarketHoliday", "Vault")
$SubDomains = @("arclight", "auth", "expo", "foundry", "iq", "motif", "svc", "ws")

#########################################

# Define some commonly used functions
function FailWithError([string] $Text)
{
	if ($global:LASTEXITCODE -lt 0)
	{
		Read-Host -Prompt "$Text ($global:LASTEXITCODE)"
		exit -1
	}
}