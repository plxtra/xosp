#Requires -PSEDition Core -Version 7
param (
	[string[]] $Accounts, # Format OWNER:ACCOUNT
	[string] $Currency,
	[decimal] $Amount,
	[switch] $OnlyIfZero
)

# This script deposits the same amount of a given currency across multiple accounts

#########################################

$Accounts | ForEach-Object -ThrottleLimit 4 -Parallel {
	& /tasks/account-deposit.ps1 -Account $_ -Currency $using:Currency -Amount $using:Amount -OnlyIfZero:($using:OnlyIfZero)
}