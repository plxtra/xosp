#Requires -PSEDition Core -Version 7
param (
	[String] $OwnerCode,
	[String] $OwnerName
)

#########################################

# Execute the Shared Module script
. "/tasks/init-params.ps1"
. "/tasks/common.ps1"

$FoundryControl = "/app/foundry/Paritech.Foundry.Control.dll"

# Some default parameters
$BalancesName = 'Balances'
$HoldingsName = 'Holdings'
$DepositsName = 'CashDeposits'
$TokenIssueName = 'TokenIssue'

$SourcePath = $PSScriptRoot
$CurrenciesFile = Join-Path $SourcePath "currencies.csv"
$Currencies = Import-Csv -Path $CurrenciesFile

#########################################

& dotnet $FoundryControl IdentitySource Define XOSP Auth "XOSP Auth Server" -Auth Jwt -Param Issuer $TokenService -Param Audience "Foundry$AuthSuffix-API" | Out-Null

Write-Host '.' -NoNewline

& dotnet $FoundryControl Identity Define XOSP Auth "Client:Foundry$AuthSuffix`$Control" -Type System -Feature Admin -Feature Audit -Feature DefineSystem -Feature Define -Feature MaintainRecords -Feature SubmitRecords | Out-Null

Write-Host '.' -NoNewline

# Exercise the REST API to configure the registry top-level systems
$OperatorClassID = & dotnet $FoundryControl EntityClass DefineTopLevel XOSP "RegistryOperator" -Desc "Asset Registry Operator"
$OperatorEntityID = & dotnet $FoundryControl Entity Define XOSP $OperatorClassID $OwnerCode -TopLevel -Desc $OwnerName
& dotnet $FoundryControl Identity Define XOSP Auth "Client:Foundry$AuthSuffix`$Service" -Type Service -Feed Prodigy -Feed OMS -Entity $OperatorEntityID | Out-Null

Write-Host '.' -NoNewline

# Exercise the REST API to configure the registry structure
# Define Entity Classes
$RegistryClassID = & dotnet $FoundryControl EntityClass Define XOSP $OperatorEntityID "Registry" -Desc "Security Token Registry" -Meta OmsPurpose Exchange
$IssuerClassID = & dotnet $FoundryControl EntityClass Define XOSP $OperatorEntityID "Issuer" -Desc "Security Token Issuer"
$InvestorClassID = & dotnet $FoundryControl EntityClass Define XOSP $OperatorEntityID "Investor" -Desc "Investing Entity"
$AccountClassID = & dotnet $FoundryControl EntityClass Define XOSP $OperatorEntityID "TradingAccount" -Desc "Investor Trading Account"

Write-Host '.' -NoNewline

# Define Asset Classes
$CurrencyClassID = & dotnet $FoundryControl AssetClass Define XOSP $OperatorEntityID "Currency" -Desc "Currency"
$TokenClassID = & dotnet $FoundryControl AssetClass Define XOSP $OperatorEntityID "Token" -Desc "Security Token"

Write-Host '.' -NoNewline

# Define Entity Associations
& dotnet $FoundryControl EntityAssociation Define XOSP $IssuerClassID $OperatorClassID "OperatorToIssuer" -Desc "Links Registry Operators and Issuers" -Primary | Out-Null
& dotnet $FoundryControl EntityAssociation Define XOSP $InvestorClassID $OperatorClassID "OperatorToInvestor" -Desc "Links Registry Operators and Investors" -Primary | Out-Null
& dotnet $FoundryControl EntityAssociation Define XOSP $RegistryClassID $OperatorClassID "OperatorToRegistry" -Desc "Links Registry Operators and Registries" -Primary | Out-Null
& dotnet $FoundryControl EntityAssociation Define XOSP $AccountClassID $InvestorClassID "InvestorToAccount" -Desc "Links Investors to Trading Accounts" -Primary | Out-Null

Write-Host '.' -NoNewline

# Define Asset Associations
& dotnet $FoundryControl AssetAssociation Define XOSP $CurrencyClassID $OperatorClassID "OperatorToCurrency" -Desc "Links Registry Operators and Currencies" -Parent | Out-Null
& dotnet $FoundryControl AssetAssociation Define XOSP $TokenClassID $IssuerClassID "IssuerToToken" -Desc "Links Issuers and Security Tokens" -Parent | Out-Null
& dotnet $FoundryControl AssetAssociation Define XOSP $TokenClassID $RegistryClassID "RegistryToToken" -Desc "Links Token Registries and Security Tokens" -Friend | Out-Null

Write-Host '.' -NoNewline

# Define Asset Attributes
& dotnet $FoundryControl AssetAttribute Define XOSP $CurrencyClassID String CurrencyCode -Desc "ISO Currency Code" -Meta OmsPurpose CurrencyCode | Out-Null
& dotnet $FoundryControl AssetAttribute Define XOSP $TokenClassID String Symbol -Desc "Symbol Code" | Out-Null
& dotnet $FoundryControl AssetAttribute Define XOSP $TokenClassID String ISIN -Desc "ISIN Instrument Identifier" | Out-Null
& dotnet $FoundryControl AssetAttribute Define XOSP $TokenClassID String PrimaryCurrency -Desc "Primary currency for this Token, as an ISO Currency Code" | Out-Null

Write-Host '.' -NoNewline

# Define Entity Attributes
& dotnet $FoundryControl EntityAttribute Define XOSP $OperatorClassID String OmsOwner -Desc "The OMS EntityCode to match in Execution Reports for this Operator" | Out-Null
& dotnet $FoundryControl EntityAttribute Define XOSP $InvestorClassID String Country -Desc "Investor ISO Country Code" | Out-Null
& dotnet $FoundryControl EntityAttribute Define XOSP $InvestorClassID String PIIHash -Desc "Investor Personally Identifiable Information Hash" | Out-Null
& dotnet $FoundryControl EntityAttribute Define XOSP $InvestorClassID String FullName -Desc "Full Legal Name" | Out-Null
& dotnet $FoundryControl EntityAttribute Define XOSP $IssuerClassID String LEI -Desc "Issuer Legal Entity Identifier" | Out-Null
& dotnet $FoundryControl EntityAttribute Define XOSP $RegistryClassID String Registry -Desc "Issuing Registry Code" | Out-Null
& dotnet $FoundryControl EntityAttribute Define XOSP $RegistryClassID String FixExecutingFirm -Desc "The Executing Firm to match in Execution Reports for this registry" | Out-Null

Write-Host '.' -NoNewline

# Define Currencies
foreach ($Currency in $Currencies.GetEnumerator())
{
	$CurrencyID = & dotnet $FoundryControl Asset Define XOSP $CurrencyClassID $Currency.Code -Owner $OperatorEntityID -Desc $Currency.Name
	& dotnet $FoundryControl Asset Set XOSP $CurrencyID -ByName CurrencyCode $Currency.Code | Out-Null
}

Write-Host '.' -NoNewline

# Configure some top-level system attributes
& dotnet $FoundryControl Entity Set XOSP $OperatorEntityID -ByName OmsOwner $OwnerCode | Out-Null

Write-Host '.' -NoNewline

# Define the Ledgers
$TokenIssueLedgerID = & dotnet $FoundryControl Ledger Define XOSP $OperatorEntityID Equity $TokenIssueName -Asset $TokenClassID -Entity $IssuerClassID -Desc "Security Token Issue" -Meta OmsPurpose Issues
$HoldingsLedgerID = & dotnet $FoundryControl Ledger Define XOSP $OperatorEntityID Asset $HoldingsName -Asset $TokenClassID -Entity $AccountClassID -Desc "Trading Account Token Holdings" -Meta OmsPurpose Balances
$BalancesLedgerID = & dotnet $FoundryControl Ledger Define XOSP $OperatorEntityID Asset $BalancesName -Asset $CurrencyClassID -Entity $AccountClassID -Desc "Trading Account Cash Balances" -Meta OmsPurpose Holdings
$DepositsLedgerID = & dotnet $FoundryControl Ledger Define XOSP $OperatorEntityID Liability $DepositsName -Asset $CurrencyClassID -Entity $OperatorClassID -Desc "Investor Cash Deposits" -Meta OmsPurpose Deposits

Write-Host '.' -NoNewline

# Define the Data Types for the records the system can accept. Tag them for the adapters to recognise
$TradeTypeID = & dotnet $FoundryControl Type Define XOSP $OperatorEntityID $OperatorClassID FIX ProdigyTrade -Meta FixExecType Trade
$CancelTypeID = & dotnet $FoundryControl Type Define XOSP $OperatorEntityID $OperatorClassID FIX ProdigyCancellation -Meta FixExecType TradeCancel
$CorrectTypeID = & dotnet $FoundryControl Type Define XOSP $OperatorEntityID $OperatorClassID FIX ProdigyCorrection
#$OmsTradeTypeID = & dotnet $FoundryControl Type Define XOSP $OperatorEntityID $OperatorClassID JSON OmsTrade -Meta OmsTradeType Trade
$ManualCrossHoldingTypeID = & dotnet $FoundryControl Type Define XOSP $OperatorEntityID $OperatorClassID JSON ManualCrossHolding
$ManualCrossBalanceTypeID = & dotnet $FoundryControl Type Define XOSP $OperatorEntityID $OperatorClassID JSON ManualCrossBalance
$ManualExternalTypeID = & dotnet $FoundryControl Type Define XOSP $OperatorEntityID $OperatorClassID JSON ManualExternal
$ManualIssueTypeID = & dotnet $FoundryControl Type Define XOSP $OperatorEntityID $OperatorClassID JSON ManualIssue

Write-Host '.' -NoNewline

# Define the Execution Strategies
& dotnet $FoundryControl Strategy Define XOSP $OperatorEntityID "Prodigy.Trade" "Prodigy Trade Execution" -Ref DataType DataType $TradeTypeID -Ref Balances Ledger $BalancesLedgerID -Ref Holdings Ledger $HoldingsLedgerID | Out-Null
& dotnet $FoundryControl Strategy Define XOSP $OperatorEntityID "Prodigy.TradeCancel" "Prodigy Trade Cancellation" -Ref DataType DataType $CancelTypeID -Ref Balances Ledger $BalancesLedgerID -Ref Holdings Ledger $HoldingsLedgerID | Out-Null
& dotnet $FoundryControl Strategy Define XOSP $OperatorEntityID "Prodigy.TradeCorrect" "Prodigy Trade Correction" -Ref DataType DataType $CorrectTypeID -Ref Balances Ledger $BalancesLedgerID -Ref Holdings Ledger $HoldingsLedgerID | Out-Null
& dotnet $FoundryControl Strategy Define XOSP $OperatorEntityID "Standard.Cross" "Manual Holdings Transfer" -Ref DataType DataType $ManualCrossHoldingTypeID -Ref Balances Ledger $HoldingsLedgerID -Meta ToOms True | Out-Null
& dotnet $FoundryControl Strategy Define XOSP $OperatorEntityID "Standard.Cross" "Manual Balance Transfer" -Ref DataType DataType $ManualCrossBalanceTypeID -Ref Balances Ledger $BalancesLedgerID -Meta ToOms True | Out-Null
& dotnet $FoundryControl Strategy Define XOSP $OperatorEntityID "Standard.External" "Manual External Transfer" -Ref DataType DataType $ManualExternalTypeID -Ref Balances Ledger $BalancesLedgerID -Ref Deposits Ledger $DepositsLedgerID -Ref ContraEntity Entity $OperatorEntityID -Meta ToOms True | Out-Null
& dotnet $FoundryControl Strategy Define XOSP $OperatorEntityID "Standard.Issue" "Manual Token Issue" -Ref DataType DataType $ManualIssueTypeID -Ref Investor Ledger $HoldingsLedgerID -Ref Issuer Ledger $TokenIssueLedgerID -Meta ToOms True | Out-Null

Write-Host '.'