#Requires -PSEDition Core -Version 7

#########################################

if (!(Test-Path "/init/init-params.json") -or !(Test-Path "/tasks/task-params.json"))
{
	Write-Warning "Unable to find parameters. Did you run XOSP-Configure.ps1 first?"
	
	exit -1
}

if (!(Test-Path "/init/auth-secrets.csv"))
{
	Write-Warning "Unable to find client secrets. Did you run XOSP-Configure.ps1?"
	
	exit -1
}

# Read in the environment configuration 
$Parameters = Get-Content "/init/init-params.json" -Raw | ConvertFrom-Json -AsHashtable

# Execute our various sub-scripts. Dot sourcing to share the execution context and inherit any variables
. "/tasks/common.ps1"

#########################################

$Extensions = @()
$ExtensionPath = "/init/Extensions" # Where to find any extensions

if ($null -ne $Parameters.Extensions -and $Parameters.Extensions.Count -gt 0 -and (Test-Path $ExtensionPath))
{
	$ExtensionFactories = @{}

	# Detect and create the extension factories
	foreach ($ExtensionFile in (Get-ChildItem (Join-Path $ExtensionPath "*") -File -Include @("*.ps1") | Foreach-Object { $_.FullName }))
	{
		$Factory = & $ExtensionFile

		$ExtensionFactories[$Factory.Name] = $Factory
	}

	# Instantiate each extension by name
	foreach ($Settings in $Parameters.Extensions.GetEnumerator())
	{
		$Factory = $ExtensionFactories[$Settings.Name]

		if ($null -eq $Factory)
		{
			Write-Host "Extension $($Settings.Name) does not exist"

			exit
		}

		$Extensions += $Factory.Create($Settings)
	}
}

#########################################

$SecretsSource = Import-Csv "/init/auth-secrets.csv"

foreach ($Record in $SecretsSource)
{
	$Parameters['ClientID-' + $Record.Application] = $Record.ClientID
	$Parameters['ClientSecret-' + $Record.Application] = $Record.ClientSecret
	$Parameters['ClientSecret-' + $Record.Application + 'UrlEncoded'] = [Uri]::EscapeDataString($Record.ClientSecret)
}

#########################################

# TODO: Exercise the REST API to populate the FIX sessions
#Write-Host "`tFIX Server." -NoNewline
#& "/init/fix-init.ps1" -OwnerCode $Parameters.MarketOperator -OwnerName $Parameters.MarketOperatorName

# Exercise the REST API to populate the auth configuration and system metadata
Write-Host "`tOMS Environment." -NoNewline
& "/init/oms-init.ps1" -OwnerCode $Parameters.MarketOperator -OwnerName $Parameters.MarketOperatorName
FailWithError "Unable to initialise the OMS Environment."

Write-Host "`tFoundry Environment." -NoNewline
# Exercise the REST API to populate the initial setup
& "/init/foundry-init.ps1" -OwnerCode $Parameters.MarketOperator -OwnerName $Parameters.MarketOperatorName

# Exercise the REST API to populate the data permissions for Expo
Write-Host "`tAuthority Environment." -NoNewline
& "/init/authority-init.ps1" -ClientIds $Parameters["ClientID-ExpoService"] -MarketAssociations $Parameters.MarketCode

# Exercise the REST API to populate the default session permissions
Write-Host "`tSessions Environment." -NoNewline
& "/init/sessions-init.ps1"

#########################################

# Populate the Market(s) and Symbols (depends on Prodigy and Foundry)
Write-Host "`tDefault Market $($Parameters.MarketCode)..."
& "/tasks/market-create.ps1" -MarketCode $Parameters.MarketCode -MarketDesc $Parameters.MarketName -OwnerCode $Parameters.MarketOperator -TimeZone $Parameters.MarketTimeZone
FailWithError "Failed to prepare Market."

if ($Parameters.AutoPopulateSymbols -gt 0)
{
	#AutoSymbolList is formatted into a string that we can pass to pwsh -Command and generate a proper string array
	$AutoSymbolList = & "/tasks/symbol-create-bulk.ps1" -MarketCode $Parameters.MarketCode -StartFrom 1 -Count $Parameters.AutoPopulateSymbols -SymbolTemplate $Parameters.AutoPopulateSymbolsTemplate
	FailWithError "Failed to auto populate symbols."
}
else
{
	$AutoSymbolList = '' # AutoSymbolList will be in the format 'CODE.MARKET',...
}

#########################################

# Create some initial Trading Accounts
if ($Parameters.AutoPopulateAccounts -gt 0)
{
	Write-Host "`tDefault Trading Accounts..."
	#AutoAccountList is formatted into a string that we can pass to pwsh -Command and generate a proper string array
	$AutoAccountList = & "/tasks/account-create-bulk.ps1" -OwnerCode $Parameters.MarketOperator -StartFrom 1 -Count $Parameters.AutoPopulateAccounts -AccountTemplate $Parameters.AutoPopulateAccountTemplate -Currency $Parameters.Currency
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
$Markets = @($Parameters.MarketCode)
$SampleMarkets = @()

# Include any extensions
foreach ($Extension in $Extensions)
{
	$Markets += $Extension.GetMarkets()
	$SampleMarkets += $Extension.GetSampleMarkets()
}

Write-Host "`tAdmin User $($Parameters.AdminUser)." -NoNewline

$UserID = & "/tasks/user-create.ps1" -UserName $Parameters.AdminUser -Password $Parameters.AdminPassword -Email $Parameters.AdminEmail -Currency $Parameters.Currency -AccountAssociations $AutoAccountList -MarketAssociations $Markets -SampleMarketAssociations $SampleMarkets -Roles $AdminRoles

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
