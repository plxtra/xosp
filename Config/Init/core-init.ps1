#Requires -PSEDition Core -Version 7

#########################################

if (!(Test-Path "/tasks/init-params.ps1"))
{
	Write-Warning "Unable to find parameters. Did you run XOSP-Configure.ps1 first?"
	
	exit -1
}

if (!(Test-Path "/init/auth-secrets.csv"))
{
	Write-Warning "Unable to find client secrets. Did you run XOSP-Configure.ps1?"
	
	exit -1
}

# Execute our various sub-scripts. Dot sourcing to share the execution context and inherit any variables
. "/init/init-defaults.ps1"
. "/init/init-params.ps1"
. "/tasks/common.ps1"

#########################################

$SecretsSource = Import-Csv -Path "/init/auth-secrets.csv"

foreach ($Record in $SecretsSource)
{
	$Parameters['ClientID-' + $Record.Application] = $Record.ClientID
	$Parameters['ClientSecret-' + $Record.Application] = $Record.ClientSecret
	$Parameters['ClientSecret-' + $Record.Application + 'UrlEncoded'] = [Uri]::EscapeDataString($Record.ClientSecret)
}

#########################################

# Exercise the REST API to populate the auth configuration and system metadata
Write-Host "`tOMS Environment." -NoNewline
& "/init/oms-init.ps1" -OwnerCode $Parameters.MarketOperator -OwnerName $Parameters.MarketOperatorName
FailWithError "Unable to initialise the OMS Environment."

Write-Host "`tFoundry Environment." -NoNewline
# Exercise the REST API to populate the initial setup
& "/init/foundry-init.ps1" -OwnerCode $Parameters.MarketOperator -OwnerName $Parameters.MarketOperatorName

# Exercise the REST API to populate the data permissions for Expo
Write-Host "`tVault Environment." -NoNewline
& "/init/vault-init.ps1" -ClientIds $Parameters["ClientID-ExpoService"] -MarketAssociations $Parameters.MarketCode

# Exercise the REST API to populate the default session permissions
Write-Host "`tSessions Environment." -NoNewline
& "/init/sessions-init.ps1"

#########################################

# Populate the Market(s) and Symbols (depends on Prodigy and Foundry)
Write-Host "`tDefault Market $($Parameters.MarketCode)..."
& "/tasks/market-create.ps1" -MarketCode $Parameters.MarketCode -MarketDesc $Parameters.MarketName -OwnerCode $Parameters.MarketOperator -TimeZone $Parameters.MarketTimeZone
FailWithError "Failed to prepare Market."

if ($AutoPopulateSymbols -gt 0)
{
	#AutoSymbolList is formatted into a string that we can pass to pwsh -Command and generate a proper string array
	$AutoSymbolList = & "/tasks/symbol-create-bulk.ps1" -MarketCode $Parameters.MarketCode -StartFrom 1 -Count $AutoPopulateSymbols -SymbolTemplate $AutoPopulateSymbolsTemplate
	FailWithError "Failed to auto populate symbols."
}
else
{
	$AutoSymbolList = '' # AutoSymbolList will be in the format 'CODE.MARKET',...
}

#########################################

# Create some initial Trading Accounts
if ($AutoPopulateAccounts -gt 0)
{
	Write-Host "`tDefault Trading Accounts..."
	#AutoAccountList is formatted into a string that we can pass to pwsh -Command and generate a proper string array
	$AutoAccountList = & "/tasks/account-create-bulk.ps1" -OwnerCode $Parameters.MarketOperator -StartFrom 1 -Count $AutoPopulateAccounts -AccountTemplate $AutoPopulateAccountTemplate -Currency $Parameters.Currency
	FailWithError "Failed to auto populate accounts."
}
else
{
	$AutoAccountList = '' # AutoAccountList will be in the format of 'OWNER:ACCOUNT',...
}

#########################################

# Create an initial login, associating the Trading Accounts and Market from above
#$AdminRoles = @("Zenith$($Parameters.AuthSuffix):Administrator")
$AdminRoles = @()

Write-Host "`tAdmin User $($Parameters.AdminUser)." -NoNewline

$UserID = & "/tasks/user-create.ps1" -UserName $Parameters.AdminUser -Password $Parameters.AdminPassword -Email $Parameters.AdminEmail -Currency $Parameters.Currency -AccountAssociations $AutoAccountList -MarketAssociations $Parameters.MarketCode -Roles $AdminRoles

& "/tasks/user-register-foundry.ps1" -UserID $UserID -Features @("Admin", "Audit", "SubmitRecords", "Operations", "Define", "DefineSystem") -Classes @("RegistryOperator")

Write-Host "`t`tUser ID $UserID"

if ($AutoAccountList.length -gt 0)
{
	Write-Host "`tDefault Balances and Holdings..."
	# Provide an initial cash balances
	& "/tasks/account-deposit-bulk.ps1"   -Accounts $AutoAccountList -Currency $Parameters.Currency -Amount 10000 -OnlyIfZero

	if ($AutoSymbolList.length -gt 0)
	{
		# Provide an initial set of holdings
		& "/tasks/account-issue-bulk.ps1" -Accounts $AutoAccountList -Symbols $AutoSymbolList -Amount 1000 -OnlyIfZero
	}
}
