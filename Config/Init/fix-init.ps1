#Requires -PSEDition Core -Version 7
param (
	[string] $OwnerCode,
	[string] $OwnerName,
	[string] $MarketCode,
	[string] $ZenithClient,
	[string] $OmsClient,
	[string] $FoundryClient,
	[string] $BaseUri = "http://prodigy.internal"
)

#########################################

function Sync-Entity
{
	param (
		[String] $BaseUri,
		[String] $EntityCode,
		[String] $EntityName,
		[switch] $IsPerson
	)
	
	$Body = @{
		"Name" = $EntityName; "Type" = $IsPerson ? "Person" : "Organisation"
		} | ConvertTo-Json
	
	$Response = Invoke-WebRequest -Uri "$BaseUri/entity/$OwnerCode" -Method Post -ContentType "application/json" -Body $Body -MaximumRedirection 0 -SkipHttpErrorCheck -ErrorAction Ignore

	if ($Response.StatusCode -ne 409 -and $Response.StatusCode -ne 302)
	{
		Write-Warning "Failure creating Entity ${EntityCode}: $($Response.StatusCode)"
		Write-Host $Response.Content
		
		exit -1
	}
}

function Sync-Account
{
	param (
		[String] $BaseUri,
		[Int32] $EntityID,
		[String] $Name,
		[String] $ExternalID,
		[String] $Description,
		[switch] $IsInactive,
		[switch] $HasFix,
		[switch] $HasPublic,
		[switch] $HasInternal
	)
	
	$Body = @{
		"Name" = $Name; "ExternalID" = $ExternalID; "Description" = $Description; "Status" = $IsInactive ? 'Inactive' : 'Active'; "ApplVerID" = $ApplVerId; "IsTransient" = $IsTransient
		} | ConvertTo-Json
	
	$Response = Invoke-WebRequest -Uri "$BaseUri/account" -Method Post -ContentType "application/json" -Body $Body -MaximumRedirection 0 -SkipHttpErrorCheck -ErrorAction Ignore

	if ($Response.StatusCode -ne 201 -and $Response.StatusCode -ne 302)
	{
		Write-Warning "Failure creating FIX Account: $($Response.StatusCode)"
		Write-Host $Response.Content
		
		exit -1
	}
	
	if (!($Response.Headers.Location -match "([\da-f\-]+)$"))
	{
		Write-Warning "Failure locating FIX Account: $($Response.Headers.Location)"
		
		exit -1
	}
	
	$AccountUID = $Matches.1
	
	return $AccountUID
}

function Sync-Session
{
	param (
		[String] $BaseUri,
		[Int32] $Account,
		[String] $Begin = 'FIXT1.1',
		[String[]] $Senders,
		[String[]] $Targets,
		[String[]] $Qualifier = @(),
		[String] $ApplVerId = 'FIX50SP2',
		[switch] $IsTransient
	)
	
	$Body = @{
		"BeginString" = $Begin; "Sender" = $Sender; "Target" = $Target; "Qualifier" = $Qualifier; "ApplVerID" = $ApplVerId; "IsTransient" = $IsTransient
		} | ConvertTo-Json
	
	$Response = Invoke-WebRequest -Uri "$BaseUri/account/byid/$Account/session" -Method Post -ContentType "application/json" -Body $Body -MaximumRedirection 0 -SkipHttpErrorCheck -ErrorAction Ignore

	if ($Response.StatusCode -ne 201 -and $Response.StatusCode -ne 302)
	{
		Write-Warning "Failure creating FIX Session: $($Response.StatusCode)"
		Write-Host $Response.Content
		
		exit -1
	}
	
	if (!($Response.Headers.Location -match "([\da-f\-]+)$"))
	{
		Write-Warning "Failure locating FIX Session: $($Response.Headers.Location)"
		
		exit -1
	}
	
	$SessionUID = $Matches.1
	
	return $SessionUID
}

#########################################

# If the admin user already exists (the last step in the setup) we can skip it
$UserExistsResponse = Invoke-WebRequest -Uri "$BaseUri/session/byidentity?begin=FIXT1.1&sender=XOSP&target=$OwnerCode&target=ZMD&applverid=FIX50SP2" -Method Head -MaximumRedirection 0 -SkipHttpErrorCheck -ErrorAction Ignore

if ($UserExistsResponse.StatusCode -eq 204)
{
	Write-Host "Prodigy FIX Session already initialised, skipping."
	
	exit
}

Sync-Entity -BaseUri $BaseUri -EntityCode $OwnerCode -EntityName $OwnerName

$ZenithAccount = Sync-Account -BaseUri $BaseUri -Entity $OwnerCode -Name 'XOSP-Zenith' -ExternalID "client:$ZenithClient" -Description "Zenith Data Services" -HasFix -HasPublic

$ZenithSession = Sync-Session -BaseUri $BaseUri -Account $ZenithAccount -Senders @('XOSP') -Targets @($OwnerCode, 'ZMD') -IsTransient

Add-EntityAccess -BaseUri $BaseUri -Session $ZenithSession -Entity $OwnerCode
Add-MarketAccess -BaseUri $BaseUri -Session $ZenithSession -Market $MarketCode

$OmsAccount = Sync-Account -BaseUri $BaseUri -Name 'XOSP-OMS' -ExternalID "client:$OmsClient" -Description "Order Management Services" -HasFix

$OmsSession = Sync-Session -BaseUri $BaseUri -Account $OmsAccount -Senders @('XOSP') -Targets @($OwnerCode, 'OMS')

Add-EntityAccess -BaseUri $BaseUri -Session $OmsSession -Entity $OwnerCode -CanTrade
Add-MarketAccess -BaseUri $BaseUri -Session $OmsSession -Market $MarketCode -CanTrade

$FoundryAccount = Sync-Account -BaseUri $BaseUri -Name 'XOSP-Foundry' -ExternalID "client:$FoundryClient" -Description "Foundry Registry Services" -HasFix

$FoundrySession = Sync-Session -BaseUri $BaseUri -Account $FoundryAccount -Senders @('XOSP') -Targets @($OwnerCode, 'FNDRY')

Add-EntityAccess -BaseUri $BaseUri -Session $FoundrySession -Entity $OwnerCode
Add-MarketAccess -BaseUri $BaseUri -Session $FoundrySession -Market $MarketCode