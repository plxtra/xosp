#Requires -PSEDition Core -Version 7
param (
	[string[]] $ClientIds,
	[string[]] $MarketAssociations = @(),
	[string] $ClientAssetType = "CLIENT",
	[string] $MarketAssetType = "MARKET"
)

#########################################

# Execute the shared tasks code
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