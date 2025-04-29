#Requires -PSEDition Core -Version 7
param (
	[string] $Account, # Format OWNER:ACCOUNT
	[string] $Currency,
	[decimal] $Amount,
	[switch] $OnlyWithBalance
)

# This script deposits an amount of the given currency into an account

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

if ($OnlyWithBalance)
{	
	$BalancesRaw = & dotnet $OmsControl Balance List XOSP -Owner $OwnerCode -Account $AccountCode
	FailWithError "Failed to read OMS balances for Account ${OwnerCode}:${AccountCode}"
	
	# Zero balance may be no record, or record with zero balance (but other values non-zero)
	$KnownBalances = ($BalancesRaw | ConvertFrom-Csv | Where-Object { $_.Currency -eq $Currency } | ForEach-Object { [Decimal]$_.Balance + [decimal]$_.UnbookedTransactions })
	
	if ($null -eq $KnownBalances -or $KnownBalances.Count -eq 0 -or $KnownBalances[0] -lt $Amount)
	{
		exit
	}
}

Write-Host "Withdrawing $Amount of $Currency from $Account"

if ($UsingFoundry)
{
	# Withdrawals from Foundry will flow through to OMS automatically
	
	# TODO: Submit the transaction record
	& dotnet $FoundryControl Standard Withdraw XOSP
}
else
{
	# If there's no Foundry for asset tracking, we can submit deposits into OMS directly
	& dotnet $OmsControl Balance Transfer XOSP $OwnerCode $AccountCode $Currency -$Amount
	FailWithError "Failed to submit balance transfer for Account ${OwnerCode}:${AccountCode}"
}