#Requires -PSEDition Core -Version 7
$RootPath = Split-Path (Get-Location)
$SourcePath = Join-Path (Split-Path (Split-Path $RootPath)) "Projects"
$TargetPath = Join-Path $RootPath "Config" "Database"
$ScriptPath = Join-Path $TargetPath "Scripts"

$Projects = @(
	@{Project = "Paritech.Audit";             User = "audit";         Database = "Audit"},
	@{Project = "Paritech.Foundry";           User = "foundry";       Database = "Foundry"},
	@{Project = "Paritech.Prodigy";           User = "prodigy";       Database = "Prodigy"},
	@{Project = "Paritech.OMS2";              User = "oms";           Database = "OMS"},
	@{Project = "Paritech.Sessions";          User = "sessions";      Database = "Sessions"},
	@{Project = "Paritech.Herald";            User = "herald";        Database = "Herald"},
	@{Project = "Paritech.Doppler";           User = "doppler";       Database = "Doppler"},
	@{Project = "Paritech.Watchmaker";        User = "watchmaker";    Database = "Watchmaker"},
	@{Project = "MotifMarkets.MotifServices"; User = "motif";         Database = "Motif"},
	@{Project = "MotifMarkets.MarketHoliday"; User = "marketholiday"; Database = "MarketHoliday"},
	@{Project = "MotifMarkets.Vault";         User = "vault";         Database = "Vault"}
	)
	
#########################################

function Build-DbScript
{
	[CmdletBinding()]
	param (
		[String] $ProjectPath,
		[String] $OutputPath,
		[String] $TargetUser
	)
	
	# Setup default parameters
	$InputPath = Join-Path $ProjectPath "Database"

	$ScriptTypes = @("config", "table", "fk", "view", "proc")
	$Schemas = @()
	$UseTransaction = $true
	$Permissions = @(
		"EXECUTE ON ALL FUNCTIONS"
		)
	
	$ParamsScript = Join-Path $ProjectPath "CompileDb-Params.ps1"

	if (Test-Path $ParamsScript)
	{
		# Execute the parameters script. Dot sourcing to share the execution context and inherit any variables
		. $ParamsScript
	}
	
	$SourceFiles = Get-ChildItem $InputPath -Recurse -File -Include "*.sql"

	$ExtractSchemas = $Schemas.Length -eq 0

	$OutputFile = [System.IO.File]::AppendText($OutputPath)
	$OutputFile.NewLine = "`n"

	try
	{
		if ($UseTransaction -eq $true)
		{
			$OutputFile.WriteLine("BEGIN TRANSACTION;")
		}
		
		foreach ($ScriptType in $ScriptTypes)
		{
			foreach ($ScriptPath in $SourceFiles | Where-Object {$_.Name.EndsWith(".$ScriptType.sql")} | Sort-Object)
			{
				# Append to DB file. Ensure everything is just plain LF, not CRLF
				$ScriptContent = [System.IO.File]::ReadAllText($ScriptPath).Replace("`r`n", "`n")

				$OutputFile.WriteLine($ScriptContent)
				
				# Ensure we have a line-terminator at the end, for neatness when reading
				if (!($ScriptContent.EndsWith("`n")))
				{
					$OutputFile.WriteLine()
				}
				
				if (($ExtractSchemas -eq $true) -and ($ScriptContent -match '^CREATE SCHEMA (?:IF NOT EXISTS )?([\w]+)'))
				{
					$Schemas += $Matches.1
				}
			}
		}

		if ($UseTransaction -eq $true)
		{
			$OutputFile.WriteLine("COMMIT TRANSACTION;")
		}
		
		$OutputFile.Close()
		
		# Fallback if there are no schemas provided or identified
		if ($Schemas.Length -eq 0)
		{
			$Schemas = @("public")
		}
		
		return @{"Schemas" = $Schemas; "Permissions" = $Permissions}
	}
	finally
	{
		$OutputFile.Dispose()
	}
}

#########################################

# Clear old SQL files
if (Test-Path $ScriptPath)
{
	Remove-Item (Join-Path $ScriptPath *.sql)
}
else
{
	New-Item -Path $ScriptPath -ItemType Directory > $null
}

# Generate each DB population script
foreach ($SourceProject in $Projects)
{
	$ProjectName = $SourceProject.Project
	$DbUser = $SourceProject.User
	$ProjectPath = Join-Path $SourcePath $ProjectName
	$TargetScript = Join-Path $ScriptPath "$ProjectName.sql"
	
	$Results = Build-DbScript $ProjectPath $TargetScript $DbUser
	
	foreach ($Property in $Results.GetEnumerator())
	{
		$SourceProject.($Property.Key) = $Property.Value
	}
}

#########################################

$InitPath = Join-Path $TargetPath "xosp.sh"

if (Test-Path $InitPath)
{
	# Execute the parameters script. Dot sourcing to share the execution context and inherit any variables
	Remove-Item $InitPath
}
	
# Generate the shell script, ensuring we use LF for newlines
$OutputFile = [System.IO.File]::AppendText($InitPath)
$OutputFile.NewLine = "`n"

try
{
	$OutputFile.WriteLine("#!/bin/bash")
	$OutputFile.WriteLine("set -e")
	# Read from the credentials file (if it exists) and collect the database names, usernames, passwords for each schema to deploy
	$OutputFile.WriteLine('if [ -f /docker-entrypoint-initdb.d/credentials ]; then')
	$OutputFile.WriteLine('  while read -r line; do declare  "$line"; done < /docker-entrypoint-initdb.d/credentials')
	$OutputFile.WriteLine('fi')
	
	foreach ($SourceProject in $Projects | Sort-Object -Property Database)
	{
		$Database = $SourceProject.Database.ToUpper()
		$DbUser = $SourceProject.User
		$DbName = $SourceProject.Database
		$ProjectName = $SourceProject.Project
		# Get the associated details for this schema, or fallback to the defaults
		$OutputFile.WriteLine("echo `"Preparing $ProjectName...`"")
		$OutputFile.WriteLine('DatabaseName=${DBNAME_' + $Database + ":-$DbName}")
		$OutputFile.WriteLine('DatabaseUser=${DBUSER_' + $Database + ":-$DbUser}")
		$OutputFile.WriteLine('DatabasePass=${DBPASS_' + $Database + ":-$DbUser}")
		# Perform creation of the database and service user
		$OutputFile.WriteLine('psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL')
		$OutputFile.WriteLine('  CREATE USER "$DatabaseUser" WITH PASSWORD ''$DatabasePass'';')
		$OutputFile.WriteLine('  CREATE DATABASE "$DatabaseName";')
		$OutputFile.WriteLine('  GRANT CONNECT, TEMPORARY ON DATABASE "$DatabaseName" TO "$DatabaseUser";')
		$OutputFile.WriteLine("EOSQL")
		# Populate the database schema
		$OutputFile.WriteLine('psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$DatabaseName"' + " --file `"/docker-entrypoint-initdb.d/Scripts/$ProjectName.sql`"")
		# Apply schema permissions
		$OutputFile.WriteLine('psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$DatabaseName" <<-EOSQL')

		foreach ($Schema in $SourceProject.Schemas | Sort-Object)
		{
			$OutputFile.WriteLine("  GRANT USAGE ON SCHEMA $Schema TO ""`$DatabaseUser"";")
			
			foreach ($Permission in $SourceProject.Permissions | Sort-Object)
			{
				$OutputFile.WriteLine("  GRANT $Permission IN SCHEMA $Schema TO ""`$DatabaseUser"";")
			}
		}
		$OutputFile.WriteLine("EOSQL")
		
	}
	
	$OutputFile.Close()
}
finally
{
	$OutputFile.Dispose()
}