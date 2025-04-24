#Requires -PSEDition Core -Version 7
param (
	[String[]] $Accounts, # Format OWNER:ACCOUNT
	[String] $Currency,
	[Decimal] $Amount,
	[Switch] $OnlyIfZero
)

# This script deposits the same amount of a given currency across multiple accounts

#########################################

$Accounts | ForEach-Object -ThrottleLimit 4 -Parallel {
	& /tasks/account-deposit.ps1 -Account $_ -Currency $using:Currency -Amount $using:Amount -OnlyIfZero:($using:OnlyIfZero)
}