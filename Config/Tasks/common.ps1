# Grab our parameters and expand them out into variables
$private:TaskParameters = Get-Content "/tasks/task-params.json" -Raw | ConvertFrom-Json -AsHashtable

foreach ($Pair in $private:TaskParameters.GetEnumerator())
{
	Set-Variable -Name $Pair.Key -Value $Pair.Value
}

#########################################
# General methods

function FailWithError([string] $Text)
{
	if ($global:LASTEXITCODE -lt 0)
	{
		Read-Host -Prompt "$Text ($global:LASTEXITCODE)"
		exit -1
	}
}

#########################################
# Auth Server

function Get-AccessToken
{
	param (
		[String] $AuthUri,
		[String] $ClientId,
		[String] $ClientSecret,
		[String[]] $Scope
	)
	
	$Body = @{
		"grant_type" = "client_credentials";
		"scope" = $ChildAssets -join ' ';
		"client_id" = $ClientId;
		"client_secret" = $ClientSecret;
		}
		
	$Response = Invoke-WebRequest -Uri "$AuthUri/connect/token" -Method Post -ContentType "application/x-www-form-urlencoded" -Body $Body -MaximumRedirection 0 -SkipHttpErrorCheck -ErrorAction Ignore

	if ($Response.StatusCode -ne 200)
	{
		Write-Warning "Failure retrieving access token: $($Response.StatusCode) $($Response.StatusDescription)"
		Write-Information $Response.Content
		
		exit -1
	}
	
	$TokenResponse = $Response.Content | ConvertFrom-Json

	return $TokenResponse.access_token | ConvertTo-SecureString -AsPlainText
}

#########################################
# Vault

function Sync-Asset
{
	param (
		[String] $VaultUri,
		[SecureString] $AccessToken,
		[String] $Asset,
		[String] $AssetType
	)
	
	$Body = @{
		"Asset" = @{
			"AssetCode" = $Asset;
			"AssetTypeCode" = $AssetType			
			}
		} | ConvertTo-Json
	
	$Response = Invoke-WebRequest -Uri "$VaultUri/api/EnsureAsset" -Method Post -ContentType "application/json" -Body $Body -Authentication Bearer -Token $AccessToken -AllowUnencryptedAuthentication -MaximumRedirection 0 -SkipHttpErrorCheck -ErrorAction Ignore

	if ($Response.StatusCode -ne 200)
	{
		Write-Warning "Failure creating/verifying $AssetType ${Asset}: $($Response.StatusCode) $($Response.StatusDescription)"
		Write-Information $Response.Content
		
		exit -1
	}
	
	$QueryResult = $Response.Content | ConvertFrom-Json

	if (-not $QueryResult.Successful)
	{
		Write-Warning "Failure creating/verifying $AssetType ${Asset}: $($QueryResult.Reason)"
		
		exit -1;
	}
}

function Sync-Associations
{
	param (
		[String] $VaultUri,
		[SecureString] $AccessToken,
		[String] $ParentAsset,
		[String] $ParentAssetType,
		[String] $ChildAssetType,
		[String[]] $ChildAssets		
	)
	
	$Body = @{
		"FromAsset" = @{
			"AssetCode" = $ParentAsset;
			"AssetTypeCode" = $ParentAssetType			
			};
		"ToAssetTypeCode" = $ChildAssetType;
		"ToAssetCodes" = $ChildAssets
		} | ConvertTo-Json
		
	$Response = Invoke-WebRequest -Uri "$VaultUri/api/EnsureAssociations" -Method Post -ContentType "application/json" -Body $Body -Authentication Bearer -Token $AccessToken -AllowUnencryptedAuthentication -MaximumRedirection 0 -SkipHttpErrorCheck -ErrorAction Ignore

	if ($Response.StatusCode -ne 200)
	{
		Write-Warning "Failure creating/verifying associations for $ParentAssetType $ParentAsset to ${ChildAssetType}: $($Response.StatusCode) $($Response.StatusDescription)"
		Write-Information $Response.Content
		
		exit -1
	}
	
	$QueryResult = $Response.Content | ConvertFrom-Json

	if (-not $QueryResult.Successful)
	{
		Write-Warning "Failure creating/verifying associations for $ParentAssetType $ParentAsset to ${ChildAssetType}: $($QueryResult.Reason)"
		
		exit -1;
	}
}
