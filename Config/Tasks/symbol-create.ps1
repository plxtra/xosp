#Requires -PSEDition Core -Version 7
param (
	[string] $MarketCode,
	[string] $SymbolCode,
	[string] $SymbolName,
	[string] $IssuerCode,
	[string] $Currency,
	[string] $CfiCode = "EXXXXX",
	[string] $Comments = $null,
	[string] $Status = $null # Null status means inherit from the market
)

# This script registers a new Symbol with the XOSP system
# - Registers the Symbol Asset under the Market in the Foundry Registry
# - Creates the Symbol on the Market in Prodigy

#########################################

if (!(Test-Path "/tasks/task-params.json"))
{
	Write-Warning "Unable to find parameters. Did you run XOSP-Configure.ps1 first?"
	
	exit -1
}

# Execute the shared tasks code
. "/tasks/common.ps1"

$FoundryControl = "/app/foundry/Paritech.Foundry.Control.dll"
$ProdigyControl = "/app/prodigy/Paritech.Prodigy.Control.dll"

#########################################

if ($UsingFoundry)
{
	# Foundry
	$OwnerID = & dotnet $FoundryControl EntityClass Lookup XOSP $OwnerCode -TopLevel

	$IssuerClassID = & dotnet $FoundryControl EntityClass Lookup XOSP Issuer -ByOwner $OwnerID

	# Register/find the attached Issuer
	$IssuerID = & dotnet $FoundryControl Entity Define XOSP $IssuerClassID $IssuerCode -Desc $IssuerName -Owner $OwnerID

	$TokenClassID = & dotnet $FoundryControl EntityClass Lookup XOSP Token -ByOwner $OwnerID

	# Register/find the attached Issuer
	$TokenID = & dotnet $FoundryControl Entity Define XOSP $TokenClassID "${SymbolCode}.${MarketCode}" -Desc $SymbolName -Owner $IssuerID

	# TODO: Register a new Foundry Asset for the Symbol
	# TODO: Attach Symbol attributes
	
	# Find the associated Registry
	$RegistryClassID = & dotnet $FoundryControl EntityClass Lookup XOSP Registry -ByOwner $OwnerID

	$RegistryID = & dotnet $FoundryControl Entity Lookup XOSP $MarketCode -ByClass $RegistryClassID

	# Link the new symbol to it
	& dotnet $FoundryControl Entity Link XOSP $TokenID $RegistryID -ByAssociation RegistryToToken
}

# Check if the Symbol exists in Prodigy
$SymbolInfoRaw = & dotnet $ProdigyControl Symbol List XOSP $MarketCode $SymbolCode -Json
FailWithError "Failed to check for Symbol ${SymbolCode}.${MarketCode}"

if ($null -eq $SymbolInfoRaw)
{
	$SymbolInfo = $null
}
else
{
	$SymbolInfo = $SymbolInfoRaw | ConvertFrom-Json
}

if ($null -eq $SymbolInfo)
{
	#Create the Symbol in Prodigy
	$Optionals = @()
	
	if (-not [String]::IsNullOrEmpty($Status))
	{
		$Optionals += @("-Status", $Status)
	}

	if (-not [String]::IsNullOrEmpty($Comments))
	{
		$Optionals += @("-Comments", $Comments)
	}
	
	$Result = & dotnet $ProdigyControl Symbol Add XOSP $MarketCode $SymbolCode -Name $SymbolName -Currency $Currency -Cfi $CfiCode @Optionals	
	FailWithError "Failed to create Symbol ${SymbolCode}.${MarketCode}"

	if ($Result -ne "Created")
	{
	}
}