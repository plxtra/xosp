#Requires -PSEDition Core -Version 7
param (
	[String] $OwnerCode,
	[Int32] $StartFrom,
	[Int32] $Count,
	[String] $AccountTemplate,
	[String] $InvestorTemplate,
	[String] $NameTemplate = "XOSP Account {0}",
	[String] $InvestorNameTemplate = "Investor {0}",
	[String] $Currency = "AUD"
)

# This script registers a series of Trading Accounts with the XOSP system

#########################################

$AccountCodes = $StartFrom..($StartFrom + $Count - 1) | ForEach-Object -ThrottleLimit 4 -Parallel {
	$AccountCode = $_.ToString($using:AccountTemplate)
	$InvestorCode = $_.ToString($using:InvestorTemplate)
	$AccountName = [String]::Format($using:NameTemplate, $AccountCode)
	$InvestorName = [String]::Format($using:InvestorNameTemplate, $InvestorCode)
	
	& /tasks/account-create.ps1 -OwnerCode $using:OwnerCode -AccountCode $AccountCode -AccountName $AccountName -InvestorCode $InvestorCode -InvestorName $InvestorName -Currency $using:Currency
	
	if ($global:LASTEXITCODE -lt 0)
	{
		exit -1
	}
	
	# We output the generated account identifiers, so the calling script can capture them for use
	return "${using:OwnerCode}:${AccountCode}"
}

$AccountCodes | Out-String -Stream