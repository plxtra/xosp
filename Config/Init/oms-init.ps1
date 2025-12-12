#Requires -PSEDition Core -Version 7
param (
	[string] $OwnerCode,
	[string] $OwnerName
)

#########################################

# Execute the shared tasks code
. "/tasks/common.ps1"

$Environment = "XOSP"
$OmsControl = "/app/oms/Paritech.OMS2.Control.dll"

#########################################

& dotnet $OmsControl IdentitySource Define $Environment Auth "XOSP Auth Server" -Auth Jwt -Param Issuer $TokenService -Param Audience "OMS$AuthSuffix-API" | Out-Null
FailWithError "Failure defining Identity Source"

Write-Host '.' -NoNewline

# Define identities for the tools and services allowed to access OMS
$Job = @(
	@{Client="Client:OMS$AuthSuffix`$Control";     Type="Operator"; Feature=@("Admin", "Alter", "Audit"); Feed=@()},
	@{Client="Client:OMS$AuthSuffix`$Service" ;    Type="Service";  Feature=@();                          Feed=@("Prodigy")},
	@{Client="Client:Foundry$AuthSuffix`$Service"; Type="Service";  Feature=@();                          Feed=@("Foundry")} 
	@{Client="Client:Zenith$AuthSuffix`$Service";  Type="Service";  Feature=@("Operator");                Feed=@()} 
) | ForEach-Object -Parallel {
	$ExtraParams = $_.Feature.GetEnumerator() | Foreach-Object { @("-Feature", $_)}
	$ExtraParams += $_.Feed.GetEnumerator() | Foreach-Object { @("-Feed", $_)}
	& dotnet $using:OmsControl Identity Define $using:Environment Auth $_.Client -Type $_.Type @ExtraParams | Out-Null
} -AsJob
Wait-Job $Job > $null
FailJobWithError $Job "Failure defining Identities"
Remove-Job $Job

Write-Host '.' -NoNewline

# Define the main account owner
& dotnet $OmsControl Owner Define $Environment $OwnerCode -Name $OwnerName | Out-Null
FailWithError "Failure defining Owner"

Write-Host '.' -NoNewline

# Define the request statuses used
$Job = @(
	@{Name="Pending";  Params=@("-Normal", "-Transition")},
	@{Name="Queued";  Params=@("-Normal", "-CanAmend", "-CanCancel")},
	@{Name="Submitted";  Params=@("-Normal", "-Transition")},
	@{Name="Rejected";  Params=@("-Completed")},
	@{Name="Completed";  Params=@("-Normal", "-Completed")}
) | ForEach-Object -Parallel {
	$ExtraParams = $_.Params
	& dotnet $using:OmsControl Status Define $using:Environment $_.Name @ExtraParams | Out-Null
} -AsJob
Wait-Job $Job > $null
FailJobWithError $Job "Failure defining request statuses"
Remove-Job $Job

Write-Host '.'