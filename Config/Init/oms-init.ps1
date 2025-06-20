#Requires -PSEDition Core -Version 7
param (
	[string] $OwnerCode,
	[string] $OwnerName
)

#########################################

# Execute the shared tasks code
. "/tasks/common.ps1"

$OmsControl = "/app/oms/Paritech.OMS2.Control.dll"

#########################################

& dotnet $OmsControl IdentitySource Define XOSP Auth "XOSP Auth Server" -Auth Jwt -Param Issuer $TokenService -Param Audience "OMS$AuthSuffix-API" | Out-Null

Write-Host '.' -NoNewline

# Define identities for the tools and services allowed to access OMS
@(
	@{Client="Client:OMS$AuthSuffix`$Control";     Type="Operator"; Feature=@("Admin", "Alter", "Audit"); Feed=@()},
	@{Client="Client:OMS$AuthSuffix`$Service" ;    Type="Service";  Feature=@();                          Feed=@("Prodigy")},
	@{Client="Client:Foundry$AuthSuffix`$Service"; Type="Service";  Feature=@();                          Feed=@("Foundry")} 
	@{Client="Client:Zenith$AuthSuffix`$Service";  Type="Service";  Feature=@("Operator");                Feed=@()} 
) | ForEach-Object -Parallel {
	$ExtraParams = $_.Feature.GetEnumerator() | Foreach-Object { @("-Feature", $_)}
	$ExtraParams += $_.Feed.GetEnumerator() | Foreach-Object { @("-Feed", $_)}
	& dotnet $using:OmsControl Identity Define XOSP Auth $_.Client -Type $_.Type @ExtraParams | Out-Null
}

Write-Host '.' -NoNewline

# Define the main account owner
& dotnet $OmsControl Owner Define XOSP $OwnerCode -Name $OwnerName | Out-Null

Write-Host '.' -NoNewline

# Define the request statuses used by XOSP
@(
	@{Name="Pending";  Params=@("-Normal", "-Transition")},
	@{Name="Queued";  Params=@("-Normal", "-CanAmend", "-CanCancel")},
	@{Name="Submitted";  Params=@("-Normal", "-Transition")},
	@{Name="Rejected";  Params=@("-Completed")},
	@{Name="Completed";  Params=@("-Normal", "-Completed")}
) | ForEach-Object -Parallel {
	$ExtraParams = $_.Params
	& dotnet $using:OmsControl Status Define XOSP $_.Name @ExtraParams | Out-Null
}

Write-Host '.'