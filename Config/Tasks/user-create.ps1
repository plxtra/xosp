#Requires -PSEDition Core -Version 7
param (
	[string] $UserName,
	[string] $Password,
	[string] $Email,
	[string] $Currency,
	[string[]] $Roles = @(),
	[string[]] $AccountAssociations = @(),
	[string[]] $MarketAssociations = @(),
	[string[]] $SampleMarketAssociations = @(),
	[string] $UserAssetType = "USER",
	[string] $AccountAssetType = "TRADINGACCOUNT",
	[string] $MarketAssetType = "MARKET",
	[string] $SampleMarketAssetType = "SAMPLEMARKET"
)

# This script registers a new User with the XOSP system
# - Registers the user's login against the provided Auth server
# - Registers the user's permissions in Vault
#   - Markets
#   - Trading Accounts

if (!(Test-Path "/tasks/task-params.json"))
{
	Write-Warning "Unable to find parameters. Did you run XOSP-Configure.ps1 first?"
	
	exit -1
}

# Execute the shared tasks code
. "/tasks/common.ps1"

$VaultUri = "http://vault"

#########################################

function Sync-User
{
	param (
		[String] $AuthUri,
		[String] $UserName,
		[String] $Password = $null,
		[String] $Email = $null,
		[String[]] $Roles,
		[String[]] $ClaimTypes,
		[String[]] $ClaimValues
	)
	
	$Body = @{
		"UserName" = $UserName; "Email" = $Email; "EmailConfirmed" = $false; "Password" = $Password
		} | ConvertTo-Json
	
	$Response = Invoke-WebRequest -Uri "$AuthUri/user?mode=Update" -Method Post -ContentType "application/json" -Body $Body -MaximumRedirection 0 -SkipHttpErrorCheck -ErrorAction Ignore

	if ($Response.StatusCode -ne 201 -and $Response.StatusCode -ne 302)
	{
		Write-Warning "Failure creating User ${UserName}: $($Response.StatusCode) $($Response.StatusDescription)"
		Write-Information $Response.Content
		
		exit -1
	}
	
	$RegexMatch = [Regex]::Match($Response.Headers.Location, "([\da-f\-]+)$")
	
	if (-not $RegexMatch.Success)
	{
		Write-Warning "Failure locating User ${UserName}: $($Response.Headers.Location)"
		
		exit -1
	}
	
	$UserUID = $RegexMatch.Value
	
	# User was newly created, so populate
	if ($Roles.Count -gt 0)
	{
		$Body = $Roles | ConvertTo-Json -AsArray
		$Response = Invoke-WebRequest -Uri "$AuthUri/user/byid/$UserUID/role" -Method Post -ContentType "application/json" -Body $Body -MaximumRedirection 0 -SkipHttpErrorCheck -ErrorAction Ignore
		
		if ($Response.StatusCode -ne 204)
		{
			Write-Warning "Failure creating User $UserUID Roles: $($Response.StatusCode)"
			Write-Host $Response.Content
			
			exit -1
		}
	}
	
	for ($Index = 0; $Index -lt $ClaimTypes.Count; $Index++)
	{
		$ClaimType = [Uri]::EscapeDataString($ClaimTypes[$Index])
		$ClaimValue = [Uri]::EscapeDataString($ClaimValues[$Index])
		
		$Response = Invoke-WebRequest -Uri "$AuthUri/user/byid/$UserUID/claim/$ClaimType" -Method Post -ContentType "text/plain" -Body $ClaimValue -MaximumRedirection 0 -SkipHttpErrorCheck -ErrorAction Ignore
		
		if ($Response.StatusCode -ne 204)
		{
			Write-Warning "Failure creating User Role ${UserUID}, Claim ${ClaimType}: $($Response.StatusCode)"
			Write-Host $Response.Content
			
			exit -1
		}
	}
	
	return $UserUID
}

#########################################

# Register against the Auth Server
$UserID = Sync-User -AuthUri $TokenService -UserName $UserName -Password $Password -Email $UserName -Roles $Roles -ClaimTypes @() -ClaimValues @()

Write-Host "." -NoNewline

$AccessToken = Get-AccessToken -AuthUri $TokenService -ClientId $XospClientId -ClientSecret $XospClientSecret

Sync-Asset -VaultUri $VaultUri -AccessToken $AccessToken -Asset $UserID -AssetType $UserAssetType

if ($AccountAssociations.length -gt 0)
{
	Write-Host "." -NoNewline
	
	Sync-Associations -VaultUri $VaultUri -AccessToken $AccessToken -ParentAsset $UserID -ParentAssetType $UserAssetType -ChildAssetType $AccountAssetType -ChildAssets $AccountAssociations
}

if ($MarketAssociations.length -gt 0)
{
	Write-Host "." -NoNewline
	
	Sync-Associations -VaultUri $VaultUri -AccessToken $AccessToken -ParentAsset $UserID -ParentAssetType $UserAssetType -ChildAssetType $MarketAssetType -ChildAssets $MarketAssociations
}

if ($SampleMarketAssociations.length -gt 0)
{
	Write-Host "." -NoNewline
	
	Sync-Associations -VaultUri $VaultUri -AccessToken $AccessToken -ParentAsset $UserID -ParentAssetType $UserAssetType -ChildAssetType $SampleMarketAssetType -ChildAssets $SampleMarketAssociations
}

Write-Host "."

return $UserID