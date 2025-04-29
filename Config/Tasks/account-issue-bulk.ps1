#Requires -PSEDition Core -Version 7
param (
	[string[]] $Accounts, # Format OWNER:ACCOUNT
	[string[]] $Symbols, # Format SYMBOL.MARKET
	[decimal] $Amount,
	[switch] $OnlyIfZero
)

# This script issues the same amount of shares in a given symbol to multiple accounts

#########################################

$Accounts | ForEach-Object -ThrottleLimit 4 -Parallel {
	& /tasks/account-issue.ps1 -Account $_ -Symbols $using:Symbols -Amount $using:Amount -OnlyIfZero:($using:OnlyIfZero)
}