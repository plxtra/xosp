#Requires -PSEDition Core -Version 7
param (
	[String[]] $ClientIds,
	[String[]] $MarketAssociations = @(),
	[String] $ClientAssetType = "CLIENT",
	[String] $MarketAssetType = "MARKET"
)

#########################################

# Execute the Shared Module script
. "/tasks/init-params.ps1"
. "/tasks/common.ps1"

$VaultUri = "http://vault"

#########################################

$AccessToken = Get-AccessToken -AuthUri $TokenService -ClientId $XospClientId -ClientSecret $XospClientSecret

foreach ($ClientId in $ClientIds)
{
	Write-Host '.' -NoNewline
	
	Sync-Asset -VaultUri $VaultUri -AccessToken $AccessToken -Asset $ClientId -AssetType $ClientAssetType

	if ($MarketAssociations.length -gt 0)
	{
		Sync-Associations -VaultUri $VaultUri -AccessToken $AccessToken -ParentAsset $ClientId -ParentAssetType $ClientAssetType -ChildAssetType $MarketAssetType -ChildAssets $MarketAssociations
	}
}

Write-Host '.'