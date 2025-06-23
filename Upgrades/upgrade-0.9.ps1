class UpgradeEngine
{
	UpgradeEngine()
	{
	}

	[string] $TargetVersion = "0.91"

	Upgrade([string] $TargetPath, [PSObject] $Parameters, [PSObject] $ComposeArgs)
	{
		# Ensure Postgres is running
		& docker @ComposeArgs up --no-recreate --wait postgres

		$DbCredentialsFile = Join-Path $TargetPath "DbCredentials.csv"
		$CredentialSource = Import-Csv -Path $DbCredentialsFile
		
		# Install Authority database
		$Credentials = $CredentialSource | Where-Object {$_.Database -eq "Authority"}
		$DatabaseUser = $Credentials.User
		$DatabasePass = $Credentials.Password
		$DatabaseName = $Credentials.Name

		& docker @ComposeArgs exec postgres psql -U $Parameters.DbSuperUser --quiet -c "CREATE USER `"$DatabaseUser`" WITH PASSWORD '$DatabasePass'; CREATE DATABASE `"$DatabaseName`"; GRANT CONNECT, TEMPORARY ON DATABASE `"$DatabaseName`" TO `"$DatabaseUser`";"
		& docker @ComposeArgs exec postgres psql -U $Parameters.DbSuperUser --quiet -f '/docker-entrypoint-initdb.d/Scripts/Paritech.Authority.sql' $DatabaseName

		# Remove Vault database
		$Credentials = $CredentialSource | Where-Object {$_.Database -eq "Vault"}
		& docker @ComposeArgs exec postgres psql -U $Parameters.DbSuperUser --quiet -c "DROP DATABASE `"$DatabaseName`""
		& docker @ComposeArgs exec postgres psql -U $Parameters.DbSuperUser --quiet -c "DROP USER `"$DatabaseUser`";"

		# Remove it from the credentials too
		$CredentialSource | Where-Object {$_.Database -ne "Vault"} | Export-Csv -Path $DbCredentialsFile -NoTypeInformation
	}
}

return [UpgradeEngine]::new()