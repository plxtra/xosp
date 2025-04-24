#Requires -PSEDition Core -Version 7
param (
	[String] $MarketCode,
	[String] $MarketDesc,
	[String] $OwnerCode,
	[String] $TimeZone = "Etc/UTC",
	[String] $Status = "Open"
)

# This script registers a new market with the XOSP system
# - Registers the market within the Foundry Registry
# - Creates the market on the Prodigy Exchange
# - Associates it with the pre-configured FIX sessions for Foundry/OMS/Zenith, as well as any additional nominated sessions
# - Associates it with the nominated users for viewing and trading

#########################################

if (!(Test-Path "/tasks/init-params.ps1"))
{
	Write-Warning "Unable to find parameters. Did you run XOSP-Configure.ps1 first?"
	
	exit
}

# Execute the Shared Module script
. "/tasks/init-params.ps1"
. "/tasks/common.ps1"

$FoundryControl = "/app/foundry/Paritech.Foundry.Control.dll"
$ProdigyControl = "/app/prodigy/Paritech.Prodigy.Control.dll"

$MarketType = "Paritech.Prodigy.Model.Standard.StandardMarketModel, Paritech.Prodigy.Model.Standard"
$EngineType = "Paritech.Prodigy.Engines.Standard.StandardEngineProvider, Paritech.Prodigy.Engines.Standard"
$TranslatorType = "Paritech.Prodigy.Translators.Standard.StandardTranslatorProvider, Paritech.Prodigy.Translators.Standard"

#########################################

if ($UsingFoundry)
{
	# Foundry
	$OwnerID = & dotnet $FoundryControl EntityClass Lookup XOSP $OwnerCode -TopLevel

	$RegistryClassID = & dotnet $FoundryControl EntityClass Lookup XOSP Registry -ByOwner $OwnerID

	$MarketID = & dotnet $FoundryControl Entity Define XOSP $RegistryClassID $MarketCode -Owner $OwnerID -Desc $MarketDesc -Meta ToOms True
	FailWithError "Failed to define Foundry Market Entity $MarketName"

	& dotnet $FoundryControl Entity Set XOSP $MarketID -ByName Registry "$MarketName" | Out-Null
	FailWithError "Failed to set attributes for Foundry Market Entity $MarketName"

	& dotnet $FoundryControl Entity Set XOSP $MarketID -ByName FixExecutingFirm "$OwnerCode" | Out-Null
	FailWithError "Failed to set attributes for Foundry Market Entity $MarketName"
}

$AllMarketsRaw = & dotnet $ProdigyControl Market List XOSP $MarketCode
FailWithError "Failed to retrieve existing markets"

# Check if the Market exists
if (-not ($AllMarketsRaw | ConvertFrom-Csv | Select-Object -ExpandProperty Code) -contains $MarketCode)
{
	$Optionals = @()
	
	if ($MarketDesc -ne $null)
	{
		$Optionals += @("-Comments", $MarketDesc)
	}
	
	if ($Status -ne $null)
	{
		$Optionals += @("-Status", $Status)
	}
	
	if ($TimeZone -ne $null)
	{
		$Optionals += @("-TimeZone", $TimeZone)
	}
	
	$Result = & dotnet $ProdigyControl Market Create XOSP $MarketCode $MarketType $EngineType $TranslatorType @Optionals
	FailWithError "Failed to create Market $MarketCode"

	if ($Result -ne "Created")
	{
	}
}

$Result = & dotnet $ProdigyControl SessionMarket Add XOSP XOSP $OwnerCode/ZMD $MarketCode -Verify
FailWithError "Failed to register market against Session for Zenith"

$Result = & dotnet $ProdigyControl SessionMarket Add XOSP XOSP $OwnerCode/OMS $MarketCode -CanTrade -Verify
FailWithError "Failed to register market against Session for OMS"

$Result = & dotnet $ProdigyControl SessionMarket Add XOSP XOSP $OwnerCode/FNDRY $MarketCode -Verify
FailWithError "Failed to register market against Session for Foundry"