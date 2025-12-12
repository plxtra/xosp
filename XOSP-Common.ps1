# This file contains shared code for XOSP operations, and is not meant to be executed directly
param(
	[switch] $UseCoreParams,
	[string] $Version = "",
	[Parameter(ValueFromRemainingArguments=$true)]
	[Alias("Profiles")]
	[string[]] $ConfigProfiles
)

#########################################

if ($UseCoreParams)
{
	$private:ParamSource = (Join-Path $PSScriptRoot "Docker" "Init" "init-params.json")

	$Parameters = Get-Content $private:ParamSource -Raw | ConvertFrom-Json -AsHashtable
}
else
{
	# Set some defaults, which may be changed by the selected profiles and user parameters
	$private:ParamSources = @()

	# Detect each profile, whether a .json or a full script
	foreach ($ConfigProfile in $ConfigProfiles)
	{
		$private:JsonPath = Join-Path $PSScriptRoot "Profiles" "$ConfigProfile.json"

		if (Test-Path $private:JsonPath)
		{
			$private:ParamSources += $private:JsonPath

			continue
		}
		
		$private:Ps1Path = Join-Path $PSScriptRoot "Profiles" "$ConfigProfile.ps1"

		if (Test-Path $private:Ps1Path)
		{
			$private:ParamSources += $private:Ps1Path

			continue
		}

		Write-Warning "Could not find a profile with the name '$ConfigProfile'"

		exit -1
	}

	$private:ParamSources += Join-Path $PSScriptRoot "XOSP-Params.json"

	#########################################

	$Parameters = @{Version=$Version}

	# Read in and override any parameters
	foreach ($SourceParamPath in $private:ParamSources.GetEnumerator())
	{
		if ($SourceParamPath.EndsWith(".ps1"))
		{
			# Script file, so execute and retrieve the altered parameters
			$Parameters = & $SourceParamPath -Parameters $Parameters
		}
		else
		{
			$SourceParams = Get-Content -Raw $SourceParamPath | ConvertFrom-Json -AsHashtable

			foreach ($Pair in $SourceParams.GetEnumerator())
			{
				if ($Pair.Value -is [array] -and $Parameters.ContainsKey($Pair.Key))
				{
					$Parameters[$Pair.Key] += $Pair.Value
				}
				else
				{
					$Parameters[$Pair.Key] = $Pair.Value
				}
			}
		}
	}

	# Load the default values. We'll apply these to any properties not set (or set to null) by the profiles
	$private:DefaultsPath = Join-Path $PSScriptRoot "Config" "Init" "init-defaults.ps1"
	$private:Defaults = & $private:DefaultsPath -Parameters $Parameters

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

	# Some parameters are generated based on the final configuration, to make life easier in other areas

	# If we're specifying an SSL port (the default) then we want to have a suffix value we can insert into config files
	if ($Parameters.PublicHttpsPort -ne 443)
	{
		$Parameters.HttpsSuffix = ":" + $Parameters.PublicHttpsPort
	}
	else
	{
		$Parameters.HttpsSuffix = ""
	}

	if ($Parameters.PublicHttpPort -ne 80)
	{
		$Parameters.HttpSuffix = ":" + $Parameters.PublicHttpPort
	}
	else
	{
		$Parameters.HttpSuffix = ""
	}

	$Parameters.HttpUri = $Parameters.RootDomainName + $Parameters.HttpSuffix
	$Parameters.HttpsUri = $Parameters.RootDomainName + $Parameters.HttpsSuffix

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
$Parameters.Databases = @("Audit", "Authority", "Doppler", "Foundry", "Herald", "MarketHoliday", "Motif", "OMS", "Prodigy", "Sessions", "Watchmaker")
$Parameters.SubDomains = @("arclight", "auth", "expo", "foundry", "iq", "motif", "svc", "ws")

#########################################

# Define some commonly used functions

function FailWithError([string] $Text = $null)
{
	if ($global:LASTEXITCODE -ne 0)
	{
		if ($null -ne $Text)
		{
			Write-Warning "$Text ($global:LASTEXITCODE)"
		}

		exit -1
	}
}

function FailJobWithError([System.Management.Automation.Job] $Job, [string] $Text = $null)
{
	if ($Job.State -eq "Failed" -or ($Job.ChildJobs | Where-Object { $_.State -eq "Failed" }))
	{
		if ($null -ne $Text)
		{
			Write-Warning $Text
		}
		Remove-Job $Job

		exit -1
	}
}
