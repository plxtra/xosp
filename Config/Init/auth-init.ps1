#Requires -PSEDition Core -Version 7

#########################################

$SourcePath = $PSScriptRoot
$BaseUri = "http://auth"

#########################################

function Sync-Client
{
	param (
		[String] $BaseUri,
		[String] $ClientId,
		[String] $ClientSecret,
		[String[]] $Permissions,
		[String] $DisplayName = "",
		[String] $Consent = "explicit",
		[String[]] $Uris = @(),
		[String[]] $LogoutUris = @(),
		[String[]] $Requirements = @(),
		[Boolean] $Confidential
	)
	
	$Body = @{
		"ClientId" = $ClientId; "ClientSecret" = $ClientSecret; "DisplayName" = $DisplayName;
		"Permissions" = $Permissions;  "Requirements" = $Requirements; "RedirectUris" = $Uris; "PostLogoutRedirectUris" = $LogoutUris;
		"ConsentType" = $Consent; "ClientType" = $Confidential ? "confidential" : "public"
		} | ConvertTo-Json
	
	$Response = Invoke-WebRequest -Uri "$BaseUri/client?mode=Update" -Method Post -ContentType "application/json" -Body $Body -MaximumRedirection 0 -SkipHttpErrorCheck -ErrorAction Ignore

	if ($Response.StatusCode -ne 201 -and $Response.StatusCode -ne 302)
	{
		Write-Warning "Failure creating Client Application ${ClientId}: $($Response.StatusCode)"
		Write-Host $Response.Content
		
		exit -1
	}
	
	$RegexMatch = [Regex]::Match($Response.Headers.Location, "([\da-f\-]+)$")
	
	if (-not $RegexMatch.Success)
	{
		Write-Warning "Failure locating Client Application ${ClientId}: $($Response.Headers.Location)"
		
		exit -1
	}
	
	$ClientUID = $RegexMatch.Value
	
	return $ClientUID
}

function Sync-Role
{
	param (
		[String] $BaseUri,
		[String] $Name,
		[String[]] $ClaimTypes,
		[String[]] $ClaimValues
	)
	
	$Body = @{
		"Name" = $Name
		} | ConvertTo-Json
	
	$Response = Invoke-WebRequest -Uri "$BaseUri/role?mode=Update" -Method Post -ContentType "application/json" -Body $Body -MaximumRedirection 0 -SkipHttpErrorCheck -ErrorAction Ignore

	if ($Response.StatusCode -ne 201 -and $Response.StatusCode -ne 302)
	{
		Write-Warning "Failure creating User Role ${Name}: $($Response.StatusCode)"
		Write-Host $Response.Content
		
		exit -1
	}
	
	$RegexMatch = [Regex]::Match($Response.Headers.Location, "([\da-f\-]+)$")
	
	if (-not $RegexMatch.Success)
	{
		Write-Warning "Failure locating User Role ${Name}: $($Response.Headers.Location)"
		
		exit -1
	}
	
	$RoleUID = $RegexMatch.Value
	
	if ($Response.StatusCode -ne 302)
	{
		# Role was newly created, so populate
		for ($Index = 0; $Index -lt $ClaimTypes.Count; $Index++)
		{
			$ClaimType = [Uri]::EscapeDataString($ClaimTypes[$Index])
			$ClaimValue = [Uri]::EscapeDataString($ClaimValues[$Index])
			
			$Response = Invoke-WebRequest -Uri "$BaseUri/role/byid/$RoleUID/claim/$ClaimType" -Method Post -ContentType "text/plain" -Body $ClaimValue -MaximumRedirection 0 -SkipHttpErrorCheck -ErrorAction Ignore
			
			if ($Response.StatusCode -ne 204)
			{
				Write-Warning "Failure creating User Role ${Name}, Claim ${ClaimType}: $($Response.StatusCode)"
				Write-Host $Response.Content
				
				exit -1
			}
		
		}
	}
	
	return $RoleUID
}

function Sync-Scope
{
	param (
		[String] $BaseUri,
		[String] $Name,
		[String] $DisplayName = "",
		[String] $Description = "",
		[String[]] $Resources
	)
	
	$Body = @{
		"Name" = $Name; "DisplayName" = $DisplayName; "Description" = $Description;
		"Resources" = $Resources
		} | ConvertTo-Json
	
	$Response = Invoke-WebRequest -Uri "$BaseUri/scope?mode=Update" -Method Post -ContentType "application/json" -Body $Body -MaximumRedirection 0 -SkipHttpErrorCheck -ErrorAction Ignore

	if ($Response.StatusCode -ne 201 -and $Response.StatusCode -ne 302)
	{
		Write-Warning "Failure creating OAuth Scope ${Name}: $($Response.StatusCode)"
		Write-Host $Response.Content
		
		exit -1
	}
	
	$RegexMatch = [Regex]::Match($Response.Headers.Location, "([\da-f\-]+)$")
	
	if (-not $RegexMatch.Success)
	{
		Write-Warning "Failure locating OAuth Scope ${Name}: $($Response.Headers.Location)"
		
		exit -1
	}
	
	$ScopeUID = $RegexMatch.Value
	
	return $ScopeUID
}

#########################################

Write-Host "Populating Authentication Server." -NoNewline

$ClientApplicationsFile = Join-Path $SourcePath "auth-clients.csv"
$ClientApplications = Import-Csv -Path $ClientApplicationsFile

$ScopesFile = Join-Path $SourcePath "auth-scopes.csv"
$ScopeConfiguration = Import-Csv -Path $ScopesFile

$RolesFile = Join-Path $SourcePath "auth-roles.csv"
$RolesConfiguration = Import-Csv -Path $RolesFile

$ClientSecretsFile = Join-Path $SourcePath "auth-secrets.csv"

if (Test-Path $ClientSecretsFile)
{
	$ClientSecrets = @{}
	$SecretsSource = Import-Csv -Path $ClientSecretsFile
	
	foreach ($Record in $SecretsSource)
	{
		$ClientSecrets[$Record.Application] = @{ ClientID = $Record.ClientID; Secret = $Record.ClientSecret }
	}
}
else
{
	Write-Warning "Failed to read Client Secrets, did you run XOSP-Configure?"

	exit -1
}

# All additional columns represent extra claims for each role
$ClaimTypes = $RolesConfiguration | Get-Member -MemberType NoteProperty | Where-Object { $_.Name -ne "Role" }

#########################################

Write-Host '.' -NoNewline

# Operations will not update existing structures if the definitions have changed, but will add new ones based on their key (Name, UserName, etc)
foreach ($Scope in $ScopeConfiguration)
{
	$Resources = $Scope.Resources -split ' '
	
	Sync-Scope -BaseUri $BaseUri -Name $Scope.Scope -DisplayName $Scope.DisplayName -Description $Scope.Description -Resources $Resources | Out-Null
}

Write-Host '.' -NoNewline

foreach ($Role in $RolesConfiguration)
{
	$ClaimValues = $ClaimTypes | Select-Object { $Role[$_] }
	
	Sync-Role -BaseUri $BaseUri -Name $Role.Role -ClaimTypes $ClaimTypes -ClaimValues $ClaimValues | Out-Null
}

Write-Host '.' -NoNewline

foreach ($Application in $ClientApplications)
{
	$Name = $Application.Name + $Application.Type
	$Credentials = $ClientSecrets[$Name]
	
	$Permissions = $Application.Permissions -split ' '
	$Requirements = $Application.Requirements -split ' '
	$Uris = $Application.Uris -split ' '
	$LogoutUris = $Application.LogoutUris -split ' '
	$Scopes = $Application.Scopes -split ' '
	
	$Permissions = $Permissions + ($Scopes | Foreach-Object { "scp:" + $_ })
	$Confidential = [Bool]::Parse($Application.Confidential)
	$ClientSecret = $Confidential ? $Credentials.Secret : $null
	
	$ClientID = Sync-Client -BaseUri $BaseUri -ClientId $Credentials.ClientID -ClientSecret $ClientSecret -DisplayName $Application.DisplayName -Permissions $Permissions -Requirements $Requirements -Uris $Uris -LogoutUris $LogoutUris -Confidential $Confidential
}

Write-Host '.'