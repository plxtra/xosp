# Grab our parameters and expand them out into variables
$private:TaskParameters = Get-Content "/tasks/task-params.json" -Raw | ConvertFrom-Json -AsHashtable

foreach ($Pair in $private:TaskParameters.GetEnumerator())
{
	Set-Variable -Name $Pair.Key -Value $Pair.Value
}

#########################################
# General methods

function FailWithError([string] $Text = $null)
{
	if ($global:LASTEXITCODE -ne 0)
	{
		if ($null -ne $Text)
		{
			Write-Warning "$Text ($global:LASTEXITCODE)"
		}

		exit -1
	}
}

function FailJobWithError([System.Management.Automation.Job] $Job, [string] $Text = $null)
{
	if ($Job.State -eq "Failed" -or ($Job.ChildJobs | Where-Object { $_.State -eq "Failed" }))
	{
		if ($null -ne $Text)
		{
			Write-Warning $Text
		}
		Remove-Job $Job

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
