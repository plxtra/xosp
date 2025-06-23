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

		# Apply the database changes
		& docker @ComposeArgs exec -e POSTGRES_DB=postgres postgres bash '/docker-entrypoint-initdb.d/Upgrades/from-0.9.sh'

		# Remove it from the credentials too
		$CredentialSource | Where-Object {$_.Database -ne "Vault"} | Export-Csv -Path $DbCredentialsFile -NoTypeInformation
	}
}

return [UpgradeEngine]::new()