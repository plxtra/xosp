#Requires -PSEDition Core -Version 7
param (
	[string] $Account, # Format OWNER:ACCOUNT
	[string] $Symbol, # Format SYMBOL.MARKET
	[string[]] $Symbols, # Format SYMBOL.MARKET
	[decimal] $Amount,
	[switch] $OnlyIfZero
)

# This script issues an amount of shares in the given symbol into an account

if (!(Test-Path "/tasks/task-params.json"))
{
	Write-Warning "Unable to find parameters. Did you run XOSP-Configure.ps1 first?"
	
	exit -1
}

# Execute the shared tasks code
. "/tasks/common.ps1"

$FoundryControl = "/app/foundry/Paritech.Foundry.Control.dll"
$OmsControl = "/app/oms/Paritech.OMS2.Control.dll"

#########################################

$OwnerCode, $AccountCode = $Account -Split ':',2

if ($null -eq $Symbols)
{
	$Symbols = @($Symbol)
}

if ($OnlyIfZero)
{	
	$HoldingsRaw = & dotnet $OmsControl Holding List XOSP -Owner $OwnerCode -Account $AccountCode
	FailWithError "Failed to read OMS holdings for Account ${OwnerCode}:${AccountCode}"
}

foreach ($Symbol in $Symbols)
{
	$RegexMatch = [Regex]::Match($Symbol, '([A-z0-9:.\ ()]*)\.([A-z0-9.]*)')
	
	if (-not $RegexMatch.Success)
	{
		Read-Host -Prompt  "Invalid Symbol Code $Symbol"
		exit -1
	}
	
	$SymbolCode, $MarketCode = $RegexMatch.Groups[1].Value, $RegexMatch.Groups[2].Value

	if ($OnlyIfZero)
	{
		# Zero holding may be no record, or record with zero quantity (but other values non-zero)
		$KnownHoldings = ($HoldingsRaw | ConvertFrom-Csv | Where-Object { $_.Exchange -eq $MarketCode -and $_.Code -eq $SymbolCode } | ForEach-Object { [Decimal]$_.Quantity })
		
		if ($null -ne $KnownHoldings -and $KnownHoldings.Count -gt 0 -and $KnownHoldings -notcontains [Decimal]0)
		{
			continue
		}
	}

	Write-Host "Issuing $Amount shares of $Symbol to $Account"

	if ($UsingFoundry)
	{
		# Issuances into Foundry will flow through to OMS automatically
		
		# TODO: Submit the transaction record
	& dotnet $FoundryControl Standard Issue XOSP
	}
	else
	{
		# If there's no Foundry for asset tracking, we can submit share issues into OMS directly
		& dotnet $OmsControl Holding Transfer XOSP $OwnerCode $AccountCode $MarketCode $SymbolCode $Amount
		FailWithError "Failed to submit holdings transfer for Account ${OwnerCode}:${AccountCode}"
		
	}
}