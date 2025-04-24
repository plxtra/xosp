#Requires -PSEDition Core -Version 7
param (
	[String] $OwnerCode,
	[String] $AccountCode,
	[String] $AccountName,
	[String] $InvestorCode,
	[String] $InvestorName,
	[String] $Currency,
	[String[]] $UserAssociations,
	[String] $UserAssetType = "USER",
	[String] $AccountAssetType = "TRADINGACCOUNT"
)

# This script registers a new Trading Account with the XOSP system
# - Registers the Trading Account in the Foundry Registry
# - Registers the Trading Account in the OMS
# - Associates the Trading Account with one or more users for trading

if (!(Test-Path "/tasks/init-params.ps1"))
{
	Write-Warning "Unable to find parameters. Did you run XOSP-Configure.ps1 first?"
	
	exit
}

# Execute the Shared Module script
. "/tasks/init-params.ps1"
. "/tasks/common.ps1"

$FoundryControl = "/app/foundry/Paritech.Foundry.Control.dll"
$OmsControl = "/app/oms/Paritech.OMS2.Control.dll"

#########################################

if ($UsingFoundry)
{
	# Foundry
	$OwnerID = & dotnet $FoundryControl EntityClass Lookup XOSP $OwnerCode -TopLevel

	$InvestorClassID = & dotnet $FoundryControl EntityClass Lookup XOSP Investor -ByOwner $OwnerID

	# Register/find the attached Investor
	$InvestorID = & dotnet $FoundryControl Entity Define XOSP $InvestorClassID $InvestorCode -Desc $InvestorName -Owner $OwnerID

	$AccountClassID = & dotnet $FoundryControl EntityClass Lookup XOSP TradingAccount -ByOwner $OwnerID

	# Register/find the attached Trading Account
	& dotnet $FoundryControl Entity Define XOSP $AccountClassID $AccountCode -Desc $AccountName -Owner $InvestorID
	
	# TODO: Attach Investor attributes
	# Country
	# PIIHash
	# FullName
	

	# & dotnet $FoundryControl Entity Set XOSP $InvestorID -ByName 
}

# Define Account Metadata with OMS
& dotnet $OmsControl Account Define XOSP $OwnerCode $AccountCode -Name $AccountName -Currency $Currency
FailWithError "Failed to define OMS metadata for Account ${OwnerCode}:${AccountCode}"

foreach ($UserIdentity in $UserAssociations)
{
	# TODO: Associate User with Account in Vault
}