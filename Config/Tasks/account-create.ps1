#Requires -PSEDition Core -Version 7
param (
	[string] $OwnerCode,
	[string] $AccountCode,
	[string] $AccountName,
	[string] $InvestorCode,
	[string] $InvestorName,
	[string] $Currency,
	[string[]] $UserAssociations,
	[string] $UserAssetType = "USER",
	[string] $AccountAssetType = "TRADINGACCOUNT"
)

# This script registers a new Trading Account with the XOSP system
# - Registers the Trading Account in the Foundry Registry
# - Registers the Trading Account in the OMS
# - Associates the Trading Account with one or more users for trading

if (!(Test-Path "/tasks/task-params.json"))
{
	Write-Warning "Unable to find parameters. Did you run XOSP-Configure.ps1 first?"
	
	exit -1
}

# Execute the shared tasks code
. "/tasks/common.ps1"

$Environment = "XOSP"
$FoundryControl = "/app/foundry/Paritech.Foundry.Control.dll"
$OmsControl = "/app/oms/Paritech.OMS2.Control.dll"

#########################################

if ($UsingFoundry)
{
	# Foundry
	$OwnerID = & dotnet $FoundryControl EntityClass Lookup $Environment $OwnerCode -TopLevel
	FailWithError "Failed to lookup top-level Entity Class"

	$InvestorClassID = & dotnet $FoundryControl EntityClass Lookup $Environment Investor -ByOwner $OwnerID
	FailWithError "Failed to lookup Investor Entity Class"
	
	# Register/find the attached Investor
	$InvestorID = & dotnet $FoundryControl Entity Define $Environment $InvestorClassID $InvestorCode -Desc $InvestorName -Owner $OwnerID
	FailWithError "Failed to define Investor Entity ${AccountCode}"

	$AccountClassID = & dotnet $FoundryControl EntityClass Lookup $Environment TradingAccount -ByOwner $OwnerID
	FailWithError "Failed to lookup TradingAccount Entity Class"

	# Register/find the attached Trading Account
	& dotnet $FoundryControl Entity Define $Environment $AccountClassID $AccountCode -Desc $AccountName -Owner $InvestorID
	FailWithError "Failed to define Trading Account Entity ${AccountCode}"
	
	# TODO: Attach Investor attributes
	# Country
	# PIIHash
	# FullName
	

	# & dotnet $FoundryControl Entity Set $Environment $InvestorID -ByName 
}

# Define Account Metadata with OMS
& dotnet $OmsControl Account Define $Environment $OwnerCode $AccountCode -Name $AccountName -Currency $Currency
FailWithError "Failed to define OMS metadata for Account ${OwnerCode}:${AccountCode}"

foreach ($UserIdentity in $UserAssociations)
{
	# TODO: Associate User with Account in Vault
}