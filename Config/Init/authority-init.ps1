#Requires -PSEDition Core -Version 7
param (
	[string[]] $ClientIds,
	[string[]] $MarketAssociations = @()
)

#########################################

# Execute the shared tasks code
. "/tasks/common.ps1"

$Environment = "XOSP"
$AuthorityControl = "/app/authority/Paritech.Authority.Control.dll"

#########################################

$SourcePath = $PSScriptRoot
$AssetTypesFile = Join-Path $SourcePath "asset-types.csv"
$AssetTypes = Import-Csv -Path $AssetTypesFile

foreach ($AssetType in $AssetTypes)
{
	& dotnet $AuthorityControl Type Define $Environment $AssetType.Code
	FailWithError "Failure defining Asset Type $AssetType"
}

Write-Host '.' -NoNewline

foreach ($ClientId in $ClientIds)
{
	& dotnet $AuthorityControl Asset Define $Environment Client $ClientId
	FailWithError "Failure defining Client $ClientId"

	Write-Host '.' -NoNewline
	
	if ($MarketAssociations.length -gt 0)
	{
		$MarketAssociations | ForEach-Object { @{ Type = "Market"; Code = $_ } } | ConvertTo-Csv | & dotnet $AuthorityControl Association Import $Environment Client $ClientId -StdIn -Format CSV
		FailWithError "Failure importing market permissions for Client $ClientId"
	}
}

Write-Host '.'