#Requires -PSEDition Core -Version 7
param (
	[string] $OwnerCode,
	[int] $StartFrom,
	[int] $Count,
	[string] $AccountTemplate,
	[string] $InvestorTemplate,
	[string] $NameTemplate = "XOSP Account {0}",
	[string] $InvestorNameTemplate = "Investor {0}",
	[string] $Currency = "AUD"
)

# This script registers a series of Trading Accounts with the XOSP system

#########################################

$AccountCodes = ($Job = $StartFrom..($StartFrom + $Count - 1) | ForEach-Object -ThrottleLimit 4 -Parallel {
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
} -AsJob) | Select-Object -ExpandProperty ChildJobs | ForEach-Object { Receive-Job $_ -Wait }
Wait-Job $Job > $null
FailJobWithError $Job "Failure creating Accounts"
Remove-Job $Job

$AccountCodes | Out-String -Stream