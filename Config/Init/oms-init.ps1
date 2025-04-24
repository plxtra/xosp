#Requires -PSEDition Core -Version 7
param (
	[String] $OwnerCode,
	[String] $OwnerName
)

#########################################

# Execute the Shared Module script
. "/tasks/init-params.ps1"
. "/tasks/common.ps1"

$OmsControl = "/app/oms/Paritech.OMS2.Control.dll"

#########################################

& dotnet $OmsControl IdentitySource Define XOSP Auth "XOSP Auth Server" -Auth Jwt -Param Issuer $TokenService -Param Audience "OMS$AuthSuffix-API" | Out-Null

Write-Host '.' -NoNewline

& dotnet $OmsControl Identity Define XOSP Auth "Client:OMS$AuthSuffix`$Control" -Type Operator -Feature Admin -Feature Alter -Feature Audit | Out-Null
& dotnet $OmsControl Identity Define XOSP Auth "Client:OMS$AuthSuffix`$Service" -Type Service -Feed Prodigy | Out-Null
& dotnet $OmsControl Identity Define XOSP Auth "Client:Foundry$AuthSuffix`$Service" -Type Service -Feed Foundry | Out-Null
& dotnet $OmsControl Identity Define XOSP Auth "Client:Zenith$AuthSuffix`$Service" -Type Service -Feature Operator | Out-Null

Write-Host '.' -NoNewline

& dotnet $OmsControl Owner Define XOSP $OwnerCode -Name $OwnerName | Out-Null

Write-Host '.' -NoNewline

& dotnet $OmsControl Status Define XOSP "Pending" -Normal -Transition | Out-Null
& dotnet $OmsControl Status Define XOSP "Queued" -Normal -CanAmend -CanCancel | Out-Null
& dotnet $OmsControl Status Define XOSP "Submitted" -Normal -Transition | Out-Null
& dotnet $OmsControl Status Define XOSP "Rejected" -Completed | Out-Null
& dotnet $OmsControl Status Define XOSP "Completed" -Normal -Completed | Out-Null

Write-Host '.'