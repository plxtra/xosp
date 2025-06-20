#Requires -PSEDition Core -Version 7
param (
	[string[]] $ClientIds,
	[string[]] $MarketAssociations = @()
)

#########################################

# Execute the shared tasks code
. "/tasks/common.ps1"

$AuthorityControl = "/app/authority/Paritech.Authority.Control.dll"

#########################################

$SourcePath = $PSScriptRoot
$AssetTypesFile = Join-Path $SourcePath "asset-types.csv"
$AssetTypes = Import-Csv -Path $AssetTypesFile

foreach ($AssetType in $AssetTypes)
{
	& dotnet $AuthorityControl Type Define XOSP $AssetType.Code
}

Write-Host '.' -NoNewline

foreach ($ClientId in $ClientIds)
{
	& dotnet $AuthorityControl Asset Define XOSP Client $ClientId

	Write-Host '.' -NoNewline
	
	if ($MarketAssociations.length -gt 0)
	{
		$MarketAssociations | ForEach-Object { @{ Type = "Market"; Code = $_ } } | ConvertTo-Csv | & dotnet $AuthorityControl Association Import XOSP Client $ClientId -StdIn -Format CSV
	}
}

Write-Host '.'