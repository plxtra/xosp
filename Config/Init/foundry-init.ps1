#Requires -PSEDition Core -Version 7
param (
	[string] $OwnerCode,
	[string] $OwnerName
)

#########################################

# Execute the shared tasks code
. "/tasks/common.ps1"

$FoundryControl = "/app/foundry/Paritech.Foundry.Control.dll"

$Environment = "XOSP"
$SourcePath = $PSScriptRoot
$CurrenciesFile = Join-Path $SourcePath "currencies.csv"
$Currencies = Import-Csv -Path $CurrenciesFile

#########################################

& dotnet $FoundryControl IdentitySource Define $Environment Auth "XOSP Auth Server" -Auth Jwt -Param Issuer $TokenService -Param Audience "Foundry$AuthSuffix-API" | Out-Null
FailWithError "Failure defining Identity Source"

Write-Host '.' -NoNewline

& dotnet $FoundryControl Identity Define $Environment Auth "Client:Foundry$AuthSuffix`$Control" -Type System -Feature Admin -Feature Audit -Feature DefineSystem -Feature Define -Feature MaintainRecords -Feature SubmitRecords | Out-Null
FailWithError "Failure defining Control Tool Identity"

Write-Host '.' -NoNewline

# Exercise the REST API to configure the registry top-level systems
$OperatorClassID = & dotnet $FoundryControl EntityClass DefineTopLevel $Environment "RegistryOperator" -Desc "Asset Registry Operator"
FailWithError "Failure defining Top Level"
$OperatorEntityID = & dotnet $FoundryControl Entity Define $Environment $OperatorClassID $OwnerCode -TopLevel -Desc $OwnerName
FailWithError "Failure defining Top Level Entity"
& dotnet $FoundryControl Identity Define $Environment Auth "Client:Foundry$AuthSuffix`$Service" -Type Service -Feed Prodigy -Feed OMS -Entity $OperatorEntityID | Out-Null
FailWithError "Failure defining Service Identity"

Write-Host '.' -NoNewline

# Exercise the REST API to configure the registry structure
# Define Entity Classes
$RegistryClassID, $IssuerClassID, $InvestorClassID, $AccountClassID = ($Job = @(
	@{Owner=$OperatorEntityID; Name="Registry";       Desc="Security Token Registry";  Meta=@{OmsPurpose="Exchange"}},
	@{Owner=$OperatorEntityID; Name="Issuer";         Desc="Security Token Issuer";    Meta=@{}},
	@{Owner=$OperatorEntityID; Name="Investor";       Desc="Investing Entity";         Meta=@{}},
	@{Owner=$OperatorEntityID; Name="TradingAccount"; Desc="Investor Trading Account"; Meta=@{}}
) | ForEach-Object -Parallel {
	$MetaParams = $_.Meta.GetEnumerator() | Foreach-Object { @("-Meta", $_.Key, $_.Value)}
	& dotnet $using:FoundryControl EntityClass Define $using:Environment $_.Owner $_.Name -Desc $_.Desc @MetaParams
} -AsJob) | Select-Object -ExpandProperty ChildJobs | ForEach-Object { Receive-Job $_ -Wait } # Do some juggling to ensure our results come out in order
Wait-Job $Job > $null
FailJobWithError $Job "Failure defining Entity Classes"
Remove-Job $Job

Write-Host '.' -NoNewline

# Define Asset Classes
$CurrencyClassID, $TokenClassID = ($Job = @(
	@{Owner=$OperatorEntityID; Name="Currency";       Desc="Currency"},
	@{Owner=$OperatorEntityID; Name="Token";          Desc="Security Token"}
) | ForEach-Object -Parallel {
	& dotnet $using:FoundryControl AssetClass Define $using:Environment $_.Owner $_.Name -Desc $_.Desc
} -AsJob) | Select-Object -ExpandProperty ChildJobs | ForEach-Object { Receive-Job $_ -Wait } # Do some juggling to ensure our results come out in order
Wait-Job $Job > $null
FailJobWithError $Job "Failure defining Asset Classes"
Remove-Job $Job

Write-Host '.' -NoNewline

# Define Entity Associations
$Job = @(
	@{Parent=$IssuerClassID;   Child=$OperatorClassID; Name="OperatorToIssuer";   Desc="Links Registry Operators and Issuers"},
	@{Parent=$InvestorClassID; Child=$OperatorClassID; Name="OperatorToInvestor"; Desc="Links Registry Operators and Investors" },
	@{Parent=$RegistryClassID; Child=$OperatorClassID; Name="OperatorToRegistry"; Desc="Links Registry Operators and Registries"},
	@{Parent=$AccountClassID;  Child=$InvestorClassID; Name="InvestorToAccount";  Desc="Links Investors to Trading Accounts"}
) | ForEach-Object -Parallel {
	& dotnet $using:FoundryControl EntityAssociation Define $using:Environment $_.Parent $_.Child $_.Name -Desc $_.Desc -Primary | Out-Null
} -AsJob
Wait-Job $Job > $null
FailJobWithError $Job "Failure defining Entity Associations"
Remove-Job $Job

Write-Host '.' -NoNewline

# Define Asset Associations
$Job = @(
	@{Parent=$CurrencyClassID; Child=$OperatorClassID; Name="OperatorToCurrency"; Desc="Links Registry Operators and Currencies";    Friend=$false},
	@{Parent=$TokenClassID;    Child=$IssuerClassID;   Name="IssuerToToken";      Desc="Links Issuers and Security Tokens";          Friend=$false},
	@{Parent=$TokenClassID;    Child=$RegistryClassID; Name="RegistryToToken";    Desc="Links Token Registries and Security Tokens"; Friend=$true} 
) | ForEach-Object -Parallel {
	& dotnet $using:FoundryControl AssetAssociation Define $using:Environment $_.Parent $_.Child $_.Name -Desc $_.Desc ($_.Friend ? "-Friend" : "-Parent") | Out-Null
} -AsJob
Wait-Job $Job > $null
FailJobWithError $Job "Failure defining Asset Associations"
Remove-Job $Job

Write-Host '.' -NoNewline

# Define Asset Attributes
$Job = @(
	@{Parent=$CurrencyClassID; Type="String"; Name="CurrencyCode";    Desc="ISO Currency Code";                                        Meta=@{OmsPurpose="CurrencyCode"}},
	@{Parent=$TokenClassID;    Type="String"; Name="Symbol";          Desc="Symbol Code";                                              Meta=@{}},
	@{Parent=$TokenClassID;    Type="String"; Name="ISIN";            Desc="ISIN Instrument Identifier";                               Meta=@{}} 
	@{Parent=$TokenClassID;    Type="String"; Name="PrimaryCurrency"; Desc="Primary currency for this Token, as an ISO Currency Code"; Meta=@{}} 
) | ForEach-Object -Parallel {
	$MetaParams = $_.Meta.GetEnumerator() | Foreach-Object { @("-Meta", $_.Key, $_.Value)}
	& dotnet $using:FoundryControl AssetAttribute Define $using:Environment $_.Parent $_.Type $_.Name -Desc $_.Desc @MetaParams | Out-Null
} -AsJob
Wait-Job $Job > $null
FailJobWithError $Job "Failure defining Asset Attributes"
Remove-Job $Job

Write-Host '.' -NoNewline

# Define Entity Attributes
$Job = @(
	@{Parent=$OperatorClassID; Type="String"; Name="OmsOwner";         Desc="The OMS EntityCode to match in Execution Reports for this Operator"},
	@{Parent=$InvestorClassID; Type="String"; Name="Country";          Desc="Investor ISO Country Code"},
	@{Parent=$InvestorClassID; Type="String"; Name="PIIHash";          Desc="Investor Personally Identifiable Information Hash"} 
	@{Parent=$InvestorClassID; Type="String"; Name="FullName";         Desc="Full Legal Name"} 
	@{Parent=$IssuerClassID;   Type="String"; Name="LEI";              Desc="Issuer Legal Entity Identifier"},
	@{Parent=$RegistryClassID; Type="String"; Name="Registry";         Desc="Issuing Registry Code"},
	@{Parent=$RegistryClassID; Type="String"; Name="FixExecutingFirm"; Desc="The Executing Firm to match in Execution Reports for this registry"} 
) | ForEach-Object -Parallel {
	& dotnet $using:FoundryControl EntityAttribute Define $using:Environment $_.Parent $_.Type $_.Name -Desc $_.Desc | Out-Null
} -AsJob
Wait-Job $Job > $null
FailJobWithError $Job "Failure defining Entity Attributes"
Remove-Job $Job

Write-Host '.' -NoNewline

# Define Currencies
$Currencies.GetEnumerator() | ForEach-Object -Parallel {
	$CurrencyID = & dotnet $using:FoundryControl Asset Define $using:Environment $using:CurrencyClassID $_.Code -Owner $using:OperatorEntityID -Desc $_.Name
	& dotnet $using:FoundryControl Asset Set $using:Environment $CurrencyID -ByName CurrencyCode $_.Code | Out-Null
} -AsJob
Wait-Job $Job > $null
FailJobWithError $Job "Failure defining Assets"
Remove-Job $Job

Write-Host '.' -NoNewline

# Configure some top-level system attributes
& dotnet $FoundryControl Entity Set $Environment $OperatorEntityID -ByName OmsOwner $OwnerCode | Out-Null
FailWithError "Failure setting Entity Attributes"

Write-Host '.' -NoNewline

# Define the Ledgers
$Ledgers = @{}
($Job = @(
	@{Parent=$OperatorEntityID; Class="Equity";    Name="TokenIssue";   Asset=$TokenClassID;    Entity=$IssuerClassID;   Desc="Security Token Issue";           Meta=@{OmsPurpose="Issues"}},
	@{Parent=$OperatorEntityID; Class="Asset";     Name="Holdings";     Asset=$TokenClassID;    Entity=$AccountClassID;  Desc="Trading Account Token Holdings"; Meta=@{OmsPurpose="Holdings"}},
	@{Parent=$OperatorEntityID; Class="Asset";     Name="Balances";     Asset=$CurrencyClassID; Entity=$AccountClassID;  Desc="Trading Account Cash Balances";  Meta=@{OmsPurpose="Balances"}},
	@{Parent=$OperatorEntityID; Class="Liability"; Name="CashDeposits"; Asset=$CurrencyClassID; Entity=$OperatorClassID; Desc="Investor Cash Deposits";         Meta=@{OmsPurpose="Deposits"}} 
) | ForEach-Object -Parallel {
	$MetaParams = $_.Meta.GetEnumerator() | Foreach-Object { @("-Meta", $_.Key, $_.Value)}
	$LedgerID = & dotnet $using:FoundryControl Ledger Define $using:Environment $_.Parent $_.Class $_.Name -Asset $_.Asset -Entity $_.Entity -Desc $_.Desc @MetaParams
	@{Key=$_.Name;Value=$LedgerID}
} -AsJob) | Select-Object -ExpandProperty ChildJobs | ForEach-Object { Receive-Job $_ -Wait } | ForEach-Object { $Ledgers.Add($_.Key, $_.Value) }
Wait-Job $Job > $null
FailJobWithError $Job "Failure defining Ledgers"
Remove-Job $Job

Write-Host '.' -NoNewline

# Define the Data Types for the records the system can accept. Tag them for the adapters to recognise
$DataTypes = @{}
($Job = @(
	@{Owner=$OperatorEntityID; Class=$OperatorClassID; Type="FIX";  Name="ProdigyTrade";        Meta=@{FixExecType="Trade"}},
	@{Owner=$OperatorEntityID; Class=$OperatorClassID; Type="FIX";  Name="ProdigyCancellation"; Meta=@{FixExecType="TradeCancel"}},
	@{Owner=$OperatorEntityID; Class=$OperatorClassID; Type="FIX";  Name="ProdigyCorrection";   Meta=@{}},
	#@{Owner=$OperatorEntityID; Class=$OperatorClassID; Type="JSON"; Name="OmsTrade";            Meta=@{OmsTradeType="Trade"}},
	@{Owner=$OperatorEntityID; Class=$OperatorClassID; Type="JSON"; Name="ManualCrossHolding";  Meta=@{}},
	@{Owner=$OperatorEntityID; Class=$OperatorClassID; Type="JSON"; Name="ManualCrossBalance";  Meta=@{}},
	@{Owner=$OperatorEntityID; Class=$OperatorClassID; Type="JSON"; Name="ManualExternal";      Meta=@{}},
	@{Owner=$OperatorEntityID; Class=$OperatorClassID; Type="JSON"; Name="ManualIssue";         Meta=@{}}
) | ForEach-Object -Parallel {
	$MetaParams = $_.Meta.GetEnumerator() | Foreach-Object { @("-Meta", $_.Key, $_.Value)}
	$DataTypeID = & dotnet $using:FoundryControl Type Define $using:Environment $_.Owner $_.Class $_.Type $_.Name @MetaParams
	@{Key=$_.Name;Value=$DataTypeID}
} -AsJob) | Select-Object -ExpandProperty ChildJobs | ForEach-Object { Receive-Job $_ -Wait } | ForEach-Object { $DataTypes.Add($_.Key, $_.Value) }
Wait-Job $Job > $null
FailJobWithError $Job "Failure defining Data Types"
Remove-Job $Job

Write-Host '.' -NoNewline

# Define the Execution Strategies
@(
	@{Parent=$OperatorEntityID; Type="Prodigy.Trade";        Name="Prodigy Trade Execution";    Ref=@(@{Name="DataType"; Type="DataType"; ID=$DataTypes.ProdigyTrade},        @{Name="Balances"; Type="Ledger"; ID=$Ledgers.Balances}, @{Name="Holdings"; Type="Ledger"; ID=$Ledgers.Holdings});                                                                  Meta=@{}},
	@{Parent=$OperatorEntityID; Type="Prodigy.TradeCancel";  Name="Prodigy Trade Cancellation"; Ref=@(@{Name="DataType"; Type="DataType"; ID=$DataTypes.ProdigyCancellation}, @{Name="Balances"; Type="Ledger"; ID=$Ledgers.Balances}, @{Name="Holdings"; Type="Ledger"; ID=$Ledgers.Holdings});                                                                  Meta=@{}}
	@{Parent=$OperatorEntityID; Type="Prodigy.TradeCorrect"; Name="Prodigy Trade Correction";   Ref=@(@{Name="DataType"; Type="DataType"; ID=$DataTypes.ProdigyCorrection},   @{Name="Balances"; Type="Ledger"; ID=$Ledgers.Balances}, @{Name="Holdings"; Type="Ledger"; ID=$Ledgers.Holdings});                                                                  Meta=@{}}
	@{Parent=$OperatorEntityID; Type="Standard.Cross";       Name="Manual Holdings Transfer";   Ref=@(@{Name="DataType"; Type="DataType"; ID=$DataTypes.ManualCrossHolding},  @{Name="Balances"; Type="Ledger"; ID=$Ledgers.Holdings});                                                                                                                           Meta=@{ToOms="True"}}
	@{Parent=$OperatorEntityID; Type="Standard.Cross";       Name="Manual Balance Transfer";    Ref=@(@{Name="DataType"; Type="DataType"; ID=$DataTypes.ManualCrossBalance},  @{Name="Balances"; Type="Ledger"; ID=$Ledgers.Balances});                                                                                                                           Meta=@{ToOms="True"}}
	@{Parent=$OperatorEntityID; Type="Standard.External";    Name="Manual External Transfer";   Ref=@(@{Name="DataType"; Type="DataType"; ID=$DataTypes.ManualExternal},      @{Name="Balances"; Type="Ledger"; ID=$Ledgers.Balances}, @{Name="Deposits"; Type="Ledger"; ID=$Ledgers.CashDeposits}, @{Name="ContraEntity"; Type="Entity"; ID=$OperatorEntityID}); Meta=@{ToOms="True"}}
	@{Parent=$OperatorEntityID; Type="Standard.Issue";       Name="Manual Token Issue";         Ref=@(@{Name="DataType"; Type="DataType"; ID=$DataTypes.ManualIssue},         @{Name="Investor"; Type="Ledger"; ID=$Ledgers.Holdings}, @{Name="Issuer"; Type="Ledger"; ID=$Ledgers.TokenIssue});                                                                  Meta=@{ToOms="True"}}
) | ForEach-Object -Parallel {
	$ExtraParams = $_.Ref.GetEnumerator() | ForEach-Object { @("-Ref", $_.Name, $_.Type, $_.ID)}
	$ExtraParams += $_.Meta.GetEnumerator() | ForEach-Object { @("-Meta", $_.Key, $_.Value)}
	& dotnet $using:FoundryControl Strategy Define $using:Environment $_.Parent $_.Type $_.Name @ExtraParams | Out-Null
} -AsJob
Wait-Job $Job > $null
FailJobWithError $Job "Failure defining Execution Strategies"
Remove-Job $Job

Write-Host '.'
