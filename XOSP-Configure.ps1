#Requires -PSEDition Core -Version 7

param(
	[Parameter(ValueFromRemainingArguments=$true)]
	[Alias("Profiles")]
	[string[]] $ConfigProfiles
)

$XospVersion = 0.91

#########################################

$SourcePath = Join-Path $PSScriptRoot "Config" # Where to find the configuration source files
$ExtensionPath = Join-Path $PSScriptRoot "Extensions" # Where to find any extensions
$TargetPath = Join-Path $PSScriptRoot "Docker" # Where to output the prepared configurations
$CoreParamsPath = Join-Path $TargetPath "Init" "init-params.json" # Where our compiled configuration goes
$ParamsPath = Join-Path $PSScriptRoot "XOSP-Params.json" # Where any configuration overrides go
$DefaultParamsPath = Join-Path $TargetPath "Init" "user-params.json"
$UpgradeVersion = $null

# Is this a new or existing installation?
if (Test-Path $CoreParamsPath)
{
	$CoreParameters = Get-Content $CoreParamsPath -Raw | ConvertFrom-Json -AsHashtable

	# Capture the installed version early, in case we're also changing profiles during upgrade
	$UpgradeVersion = $CoreParameters.Version

	# If we're using the older single-profile value, upgrade to the array format
	if (![String]::IsNullOrEmpty($CoreParameters.Profile))
	{
		$CoreParameters.Profiles = @($CoreParameters.Profile)
		$CoreParameters.Remove("Profile")
	}

	# Guarantee we always have at least one profile
	if ($CoreParameters.Profiles.Count -eq 0)
	{
		$CoreParameters.Profiles += "Default"
	}

	if ($ConfigProfiles -ne $CoreParameters.Profiles)
	{
		# If no profiles are specified, restore the previous selection
		if ($null -eq $ConfigProfiles -or $ConfigProfiles.Count -eq 0)
		{
			$ConfigProfiles = $CoreParameters.Profiles
		}
	}
}
else
{
	$CoreParameters = $null
	$UpgradeVersion = $XospVersion

	# If no profiles are specified, use the default
	if ($null -eq $ConfigProfiles -or $ConfigProfiles.Count -eq 0)
	{
		$ConfigProfiles = @("Default")
	}
}

# If we're reapplying to an existing installation, check if the version has changed
if ($null -ne $CoreParameters  -and $CoreParameters.Version -ne $XospVersion)
{
	$DefaultParamsPath = Join-Path $SourcePath "Init" "user-params.json"

	# The version has changed, check if the user parameters content has also changed (or been customised)	
	if ((Get-Content $ParamsPath -Raw) -ne (Get-Content $DefaultParamsPath -Raw))
	{
		# we should inform the user their parameters might no longer be valid
		$Choices = "&Reset XOSP-Params", "&Continue", "&Abort"

		$Choice = $Host.UI.PromptForChoice("XOSP Params Changed", "This XOSP version is different from your existing installation, your user parameters may need updating.", $Choices, 1)

		if ($Choice -eq 2)
		{
			Write-Host "Aborted. No changes were made."
			
			exit
		}

		if ($Choice -eq 1 -and (Test-Path $ParamsPath))
		{
			Write-Host "Version changed, resetting parameters..."

			Copy-Item -Path $DefaultParamsPath -Destination $ParamsPath
			$CoreParameters = $null
		}
	}
}

if (!(Test-Path $ParamsPath) -or (Get-Item $ParamsPath).Size -eq 0)
{
	# If there's no user parameters, we want to grab the defaults
	$DefaultParamsPath = Join-Path $TargetPath "Init" "user-params.json"

	Copy-Item -Path $DefaultParamsPath -Destination $ParamsPath
	
	Write-Host "Applying profiles: $ConfigProfiles"
}
else
{
	Write-Host "Applying existing profiles: $ConfigProfiles"
}

# Execute our common sub-script. Dot sourcing to share the execution context and inherit any variables
. (Join-Path $PSScriptRoot "XOSP-Common.ps1") @ConfigProfiles

# We want to copy the parameters for later, as we'll be sticking credentials and stuff inside the original
$CoreParameters = $Parameters.Clone()
$CoreParameters.Profiles = $ConfigProfiles
$CoreParameters.Version = $XospVersion
$CoreParameters.ComposeFiles = @("docker-compose.yml")

# Make sure to remove stuff we don't need for replacements
$Parameters.Remove("ComposeFiles")
$Parameters.Remove("Extensions")
$Parameters.Remove("Profiles")
$Parameters.Remove("Databases")
$Parameters.Remove("SubDomains")

#########################################

function Copy-WithReplace
{
	[CmdletBinding()]
	param (
		[String] $SourcePath,
		[String] $TargetPath,
		[PSObject] $Replacements
	)
	
	$SourceContent = New-Object System.Text.StringBuilder(Get-Content $SourcePath -Raw)
		
	foreach ($KeyValue in $Replacements.GetEnumerator())
	{
		$SearchValue = '${' + $KeyValue.Key + '}'
		
		$SourceContent.Replace($SearchValue, $KeyValue.Value) > $null
	}
	
	$NewContent = $SourceContent.ToString()
	
	try
	{
		Set-Content -Path $TargetPath -Value $NewContent > $null
	}
	catch
	{
		# If running while an environment is already active, Docker can hold the file open and cause Set-Content to fail
		# We can delete the file and try again, and that will usually fix the problem
		Remove-Item $TargetPath
		
		Set-Content -Path $TargetPath -Value $NewContent -Force > $null
	}
}

function New-Password
{
	[CmdletBinding()]
	param (
		[Int32] $Length
	)

	$Regex = '(?=.*\d)(?=.*[a-z])(?=.*[A-Z])(?=.*[!#$%&*+@]){' + $Length + ',}'

	do
	{
		$Password = -join ((35..38)+(33)+(42)+(43)+(48..57)+(63..90)+(97..122) | Get-Random -Count $Length | Foreach-Object {[char]$_})
	} until ( $Password -cmatch $Regex )
	
	return $Password
}

function Copy-Relative
{
	[CmdletBinding()]
	param (
		[String] $SourcePath,
		[String] $TargetPath,
		[String[]] $Include,
		[String[]] $Exclude = @()
	)

	Get-ChildItem $SourcePath -Recurse -File -Include $Include -Exclude $Exclude | ForEach-Object {
		$SourceFile = $_.FullName

		$RelativeFile = [System.IO.Path]::GetRelativePath($SourcePath, $SourceFile)

		$TargetFile = Join-Path $TargetPath $RelativeFile

		$TargetFilePath = [System.IO.Path]::GetDirectoryName($TargetFile)

		if (-not (Test-Path $TargetFilePath))
		{
			New-Item -Path $TargetFilePath -ItemType Directory > $null
		}

		Copy-Item $SourceFile $TargetFile
	}
}

#########################################

Write-Host "Validating Environment..."

# Check the line-endings on some files haven't been 'helpfully' converted to CRLF
$SourceFiles = Get-ChildItem $SourcePath -Recurse -File -Include @("*.sh", "Dockerfile") | ForEach-Object { $_.FullName }

foreach ($SourceFile in $SourceFiles)
{
	if ((Get-Content $SourceFile -Raw) -match "\r\n$")
	{
		Write-Host "Bad line-endings in $SourceFile, found CRLF instead of LF. Please check for git line-ending conversions."

		exit
	}
}

# Check for a Docker installation
if ($null -eq (Get-Command docker -ErrorAction Ignore))
{
	Write-Host "Unable to locate Docker installation. Please ensure you have Docker Engine or Docker Desktop installed."

	exit
}

# Check the Docker Engine is actually running
$DockerVersion = & docker version --format json 2>$null | ConvertFrom-Json

if ($null -eq $DockerVersion -or $null -eq $DockerVersion.Server)
{
	Write-Host "Could not connect to Docker Engine. Please ensure Docker Engine is started and running, and that the user has access."

	exit
}

if ($Parameters.RegistryUri -match "(?<id>\d+)\.dkr\.ecr\.(?<region>[\w-]+)\.amazonaws\.com")
{
	# Check for AWS CLI installation, as it's needed to login to the private registry
	if ($null -eq (Get-Command aws -ErrorAction Ignore))
	{
		Write-Host "Unable to locate AWS CLI. Please ensure you have the AWS CLI tools installed in order to use a private registry."

		exit
	}
}

#########################################

$Extensions = @()

if ($null -ne $CoreParameters.Extensions -and $CoreParameters.Extensions.Count -gt 0 -and (Test-Path $ExtensionPath))
{
	Write-Host "Loading Extensions..."

	$ExtensionFactories = @{}

	# Detect and create the extension factories
	foreach ($ExtensionFile in (Get-ChildItem (Join-Path $ExtensionPath "*") -File -Include @("*.ps1") | Foreach-Object { $_.FullName }))
	{
		$Factory = & $ExtensionFile

		$ExtensionFactories[$Factory.Name] = $Factory
	}

	# Instantiate each extension by name
	foreach ($Settings in $CoreParameters.Extensions.GetEnumerator())
	{
		$Factory = $ExtensionFactories[$Settings.Name]

		if ($null -eq $Factory)
		{
			Write-Host "Extension $($Settings.Name) does not exist"

			exit
		}

		$Extensions += $Factory.Create($Settings)
	}
}

#########################################

Write-Host "Preparing Data Files..."

# These files we perform ${} replacement on
$SourceFiles = Get-ChildItem $SourcePath -Recurse -File -Include @("*.csv") | Foreach-Object { $_.FullName }

foreach ($SourceFile in $SourceFiles)
{
	$RelativeFile = [System.IO.Path]::GetRelativePath($SourcePath, $SourceFile)
	
	$TargetFile = Join-Path $TargetPath $RelativeFile
	
	$TargetFilePath = [System.IO.Path]::GetDirectoryName($TargetFile)
	
	if (-not (Test-Path $TargetFilePath))
	{
		New-Item -Path $TargetFilePath -ItemType Directory > $null
	}
	
	Copy-WithReplace $SourceFile $TargetFile $Parameters
}

#########################################

$DbCredentials = @{}
# $Parameters.Databases populated from XOSP-Common.ps1

if ($true)
{
	$DbCredentialsFile = Join-Path $TargetPath "DbCredentials.csv"
	
	# If we already have credentials, load and validate them
	if (Test-Path $DbCredentialsFile)
	{
		Write-Host "Restoring existing Database Credentials..."
		
		$CredentialSource = Import-Csv -Path $DbCredentialsFile
		
		foreach ($Record in $CredentialSource)
		{
			if ($Record.Database -eq "" -and [System.String]::IsNullOrEmpty($Parameters.DbSuperPassword))
			{
				$Parameters.DbSuperPassword = $Record.Password
			}
			else
			{
				$DbCredentials[$Record.Database] = @{ Name = $Record.Name; User = $Record.User; Password = $Record.Password }
			}
		}
	}

	$DbSuffix = $Parameters.DbUserSuffix
	
	foreach ($Database in $CoreParameters.Databases.GetEnumerator() | Sort-Object)
	{
		if (-not $DbCredentials.ContainsKey($Database))
		{
			$DbPassword = New-Password 12
		
			$DbCredentials[$Database] = @{ Name = "$Database$DatabaseSuffix"; User = "$Database$DbSuffix".ToLower(); Password = $DbPassword }
		}
	}
	
	# If no DB super-user password is set, generate one
	if ([System.String]::IsNullOrEmpty($Parameters.DbSuperPassword))
	{
		$Parameters.DbSuperPassword = New-Password 12
	}
	
	$DbCredentials[""] = @{ Name = ""; User = $Parameters.DbSuperUser; Password = $Parameters.DbSuperPassword }
	
	$DbCredentials.GetEnumerator() | Foreach-Object { @{ Database = $_.Key; Name = $_.Value.Name; User = $_.Value.User; Password = $_.Value.Password } } | Export-Csv -Path $DbCredentialsFile -NoTypeInformation
	
	foreach ($KeyValue in $DbCredentials.GetEnumerator())
	{
		if ($KeyValue.Key -ne "")
		{
			$Parameters['DbName-' + $KeyValue.Key] = $KeyValue.Value.Name
			$Parameters['DbUser-' + $KeyValue.Key] = $KeyValue.Value.User
			$Parameters['DbPassword-' + $KeyValue.Key] = $KeyValue.Value.Password
		}	
	}
}

#########################################

$ClientSecrets = @{}

if ($true)
{
	$ClientSecretsFile = Join-Path $TargetPath "Init" "auth-secrets.csv"
	
	if (Test-Path $ClientSecretsFile)
	{
		Write-Host "Restoring existing Client Secrets..."
		
		$SecretsSource = Import-Csv -Path $ClientSecretsFile
		
		foreach ($Record in $SecretsSource)
		{
			$ClientSecrets[$Record.Application] = @{ ClientID = $Record.ClientID; Secret = $Record.ClientSecret }
		}
	}

	$ClientApplicationsFile = Join-Path $TargetPath "Init" "auth-clients.csv"
	
	$ClientApplications = Import-Csv -Path $ClientApplicationsFile

	$AuthSuffix = $Parameters.AuthSuffix
	
	foreach ($Application in $ClientApplications.GetEnumerator() | Sort-Object -Property Name,Type)
	{
		$AppName = $Application.Name
		$AppType = $Application.Type
		
		$ClientApp = "$AppName$AppType"
		
		if (-not $ClientSecrets.ContainsKey($ClientApp))
		{
			$ClientID = "$AppName$AuthSuffix`$$AppType"
			$Confidential = [Bool]::Parse($Application.Confidential)
			$ClientSecret = $Confidential ? (New-Password 12) : ""
			
			$ClientSecrets[$ClientApp] = @{ ClientID = $ClientID; Secret = $ClientSecret}
		}
	}
	
	$ClientSecrets.GetEnumerator() | ForEach-Object { @{ Application = $_.Key; ClientID = $_.Value.ClientID; ClientSecret = $_.Value.Secret } } | Export-Csv -Path $ClientSecretsFile -NoTypeInformation
	
	foreach ($KeyValue in $ClientSecrets.GetEnumerator())
	{
		$Parameters['ClientID-' + $KeyValue.Key] = $KeyValue.Value.ClientID
		$Parameters['ClientSecret-' + $KeyValue.Key] = $KeyValue.Value.Secret
		$Parameters['ClientSecret-' + $KeyValue.Key + 'UrlEncoded'] = [Uri]::EscapeDataString($KeyValue.Value.Secret)
	}
}

#########################################

Write-Host "Preparing Environment Files..."

# These files we perform ${} replacement on. In this second stage, we also have the Database and Client Application secrets
$SourceFiles = Get-ChildItem $SourcePath -Recurse -File -Include @("*.config", "*.conf", "*.json", "*.xml", "*.sh", "*.txt", "Dockerfile") -Exclude @("Database*") | ForEach-Object { $_.FullName }

foreach ($SourceFile in $SourceFiles)
{
	$RelativeFile = [System.IO.Path]::GetRelativePath($SourcePath, $SourceFile)
	
	$TargetFile = Join-Path $TargetPath $RelativeFile
	
	$TargetFilePath = [System.IO.Path]::GetDirectoryName($TargetFile)
	
	if (-not (Test-Path $TargetFilePath))
	{
		New-Item -Path $TargetFilePath -ItemType Directory > $null
	}
	
	Copy-WithReplace $SourceFile $TargetFile $Parameters
}

# These files we copy directly, no replacement
$SourceFiles = Get-ChildItem $SourcePath -Recurse -File -Include @("*.ps1") | ForEach-Object { $_.FullName }
$SourceFiles += Get-ChildItem (Join-Path $SourcePath "Branding") -Recurse -File | ForEach-Object { $_.FullName }

foreach ($SourceFile in $SourceFiles)
{
	$RelativeFile = [System.IO.Path]::GetRelativePath($SourcePath, $SourceFile)
	
	$TargetFile = Join-Path $TargetPath $RelativeFile
	
	$TargetFilePath = [System.IO.Path]::GetDirectoryName($TargetFile)
	
	if (-not (Test-Path $TargetFilePath))
	{
		New-Item -Path $TargetFilePath -ItemType Directory > $null
	}
	
	Copy-Item $SourceFile -Destination $TargetFile
}

#########################################

Write-Host "Preparing Docker Compose files for $($Parameters.RegistryUri)..."

if ($true)
{
	# Copy the base docker-compose file(s)
	Copy-Relative -SourcePath (Join-Path $SourcePath "Docker") -TargetPath $TargetPath -Include @("*.yml")
	
	# Prepare the environment file
	$SourceFile = Join-Path $SourcePath "Docker" ".env"
	$TargetFile = Join-Path $TargetPath $Parameters.DockerEnvFile
	
	Copy-WithReplace $SourceFile $TargetFile $Parameters
}

#########################################

if ($Extensions.Count -gt 0)
{
	Write-Host "Applying $($Extensions.Count) extensions..."

	$ExtensionTargetPath = Join-Path $TargetPath "Init" "Extensions"

	Copy-Relative -SourcePath $ExtensionPath -TargetPath $ExtensionTargetPath

	foreach ($Extension in $Extensions)
	{
		$Extension.Configure($TargetPath, $CoreParameters)

		if ($null -ne ($Extension | Get-Member GetComposeFiles))
		{
			$CoreParameters.ComposeFiles += $Extension.GetComposeFiles()
		}
	}
}

#########################################

if ($Parameters.GenerateCertificate -eq $true)
{
	$CertificateFile = Join-Path $TargetPath $Parameters.CertificateFile
	
	if (!(Test-Path "$CertificateFile.pfx"))
	{	
		Write-Host "Generating Certificate '$CertificateFile'..."
		
		$TargetFile = Join-Path $TargetPath $CertificateFile
		
		# Generate self-signed certificate
		# TODO: Make this generate a self-signed root cert too, which can be used for Firefox

		# The New-SelfSignedCertificate plugin only exists on Windows.
		# Since we want to be compatible with Powershell Core running on Linux, we use the native .Net primitives
		$KeyLength = 2048
		$Algorithm = [System.Security.Cryptography.HashAlgorithmName]::SHA256
		$Padding = [System.Security.Cryptography.RSASignaturePadding]::Pkcs1
		$FriendlyName = "XOSP" # Only supported when generating on Windows
		$CertificateDuration = 365
		$Passphrase = $null # No passphrase by default. Adjust Auth/appsettings.json and start.sh to include a password otherwise
		$RootDomainName = $Parameters.RootDomainName
		$DistinguishedName = "CN=$RootDomainName; C=AU; O=XOSP"
		
		# Prepare the Certificate details
		$CertSubject = [System.Security.Cryptography.X509Certificates.X500DistinguishedName]::new($DistinguishedName)
		$CertKey = [System.Security.Cryptography.RSA]::Create($KeyLength)
		
		$CertRequest = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new($CertSubject, $CertKey, $Algorithm, $Padding)
		
		$AltNames = [System.Security.Cryptography.X509Certificates.SubjectAlternativeNameBuilder]::new()
		$AltNames.AddDnsName($RootDomainName)
		$AltNames.AddDnsName("*.$RootDomainName")
		
		$KeyUsages = [System.Security.Cryptography.X509Certificates.X509KeyUsageFlags]::DataEncipherment -bor [System.Security.Cryptography.X509Certificates.X509KeyUsageFlags]::KeyEncipherment -bor [System.Security.Cryptography.X509Certificates.X509KeyUsageFlags]::DigitalSignature
		
		$EnhancedKeyUsages = [System.Security.Cryptography.OidCollection]::new()
		$EnhancedKeyUsages.Add([System.Security.Cryptography.Oid]::new("1.3.6.1.5.5.7.3.1", "Server Authentication")) > $null
		
		$CertExtensions = [System.Collections.Generic.List[System.Security.Cryptography.X509Certificates.X509Extension]]::new()
		$CertExtensions.Add([System.Security.Cryptography.X509Certificates.X509BasicConstraintsExtension]::new($false, $false, 0, $false))
		$CertExtensions.Add([System.Security.Cryptography.X509Certificates.X509KeyUsageExtension]::new($KeyUsages, $false))
		$CertExtensions.Add([System.Security.Cryptography.X509Certificates.X509SubjectKeyIdentifierExtension]::new($CertRequest.PublicKey, $false))
		$CertExtensions.Add([System.Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension]::new($EnhancedKeyUsages, $false))
		$CertExtensions.Add($AltNames.Build($false))
		
		foreach ($CertExtension in $CertExtensions)
		{
			$CertRequest.CertificateExtensions.Add($CertExtension)
		}
		
		# Generate the Certificate
		$NotBefore = [System.DateTimeOffset]::Now
		$NotAfter = [System.DateTimeOffset]::Now.AddDays($CertificateDuration)
		$Certificate = $CertRequest.CreateSelfSigned($NotBefore, $NotAfter)

		if (-not ($IsLinux -or $IsMacOS))
		{
			$Certificate.FriendlyName = $FriendlyName
		}

		# Output to the target directory
		$RawString = $Certificate.ExportCertificatePem()
		[System.IO.File]::WriteAllText("$CertificateFile.crt", $RawString)
		
		if ($Passphrase)
		{
			$Parameters = [System.Security.Cryptography.PbeParameters]::new([System.Security.Cryptography.PbeEncryptionAlgorithm]::Aes128Cbc, [System.Security.Cryptography.HashAlgorithmName]::SHA256, 600000)
			$RawString = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($Certificate).ExportEncryptedPkcs8PrivateKeyPem($Passphrase, $Parameters)
		}
		else
		{
			$RawString = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($Certificate).ExportRSAPrivateKeyPem()
		}
		[System.IO.File]::WriteAllText("$CertificateFile.key", $RawString)
	}
}

#########################################

Write-Host "Preparing environment initialisation files..."

if ($true)
{
	# Copy the base initdb scripts
	$DbTargetPath = Join-Path $TargetPath "Database"

	Copy-Relative -SourcePath (Join-Path $SourcePath "Database") -TargetPath $DbTargetPath -Include @("*.sql", "*.sh") -Exclude @("Init*")

	# The system initialisation scripts need to have replacement applied
	$SourceFiles = Get-ChildItem (Join-Path $SourcePath "Database" "Init") -Recurse -File -Include @("*.sql") | ForEach-Object { $_.FullName }

	foreach ($SourceFile in $SourceFiles)
	{
		$RelativeFile = [System.IO.Path]::GetRelativePath($SourcePath, $SourceFile)

		$TargetFile = Join-Path $TargetPath $RelativeFile

		$TargetFilePath = [System.IO.Path]::GetDirectoryName($TargetFile)

		if (-not (Test-Path $TargetFilePath))
		{
			New-Item -Path $TargetFilePath -ItemType Directory > $null
		}

		Copy-WithReplace $SourceFile $TargetFile $Parameters
	}

	# Generate the credentials file, which will get loaded by the script and used for user and database creation
	# We want a format supported by 'declare' in bash, otherwise we'd just provide the DbCredentials.csv
	$TargetFile = Join-Path $DbTargetPath "credentials"

	$OutputFile = [System.IO.File]::CreateText($TargetFile)
	$OutputFile.NewLine = "`n" # Needs the Unix newline, as it'll be read inside a linux container

	try
	{
		foreach ($Record in $DbCredentials.GetEnumerator() | Sort-Object -Property Key)
		{
			if ($Record.Key -eq "")
			{
				continue
			}

			$Database = $Record.Key.ToUpper()
			$DbName = $Record.Value.Name
			$DbUser = $Record.Value.User
			$DbPass = $Record.Value.Password

			# Whitespace is not allowed around the = sign
			$OutputFile.WriteLine("DBNAME_$Database=$DbName")
			$OutputFile.WriteLine("DBUSER_$Database=$DbUser")
			$OutputFile.WriteLine("DBPASS_$Database=$DbPass")
		}

		$OutputFile.Close()
	}
	finally
	{
		$OutputFile.Dispose()
	}

	# Generate the init parameters file, which will get loaded inside docker during environment setup
	$CoreParameters.Remove("Databases")
	$CoreParameters.Remove("SubDomains")

	$CoreParamsPath = Join-Path $TargetPath "Init" "init-params.json"
	$CoreParameters | ConvertTo-Json -Depth 100 | Set-Content $CoreParamsPath

	# Are we upgrading from a previous version?
	if ($UpgradeVersion -ne $XospVersion)
	{
		# Check there's a valid upgrade path
		$UpgradePath = Join-Path $PSScriptRoot "Upgrades" "upgrade-$UpgradeVersion.ps1"

		if (!(Test-Path $UpgradePath))
		{
			Write-Warning "No upgrade route exists from version $UpgradeVersion. Run XOSP-Clear.ps1 to reset your environment before installing."
		}
		else
		{
			$UpgradePath = Join-Path $TargetPath "Init" "upgrade-required"

			# Only replace this file if there isn't an upgrade already queued
			if (!(Test-Path $UpgradePath))
			{
				$UpgradeVersion | Set-Content $UpgradePath -NoNewLine
				
				Write-Host "Prepared upgrade from version $UpgradeVersion."
			}
		}
	}

	# Generate the task parameters file, which will get loaded by various administrative task scripts
	$TaskParameters = @{
		UsingFoundry = $false;
		TokenService = "https://auth.$($Parameters.HttpsUri)";
		AuthSuffix = $Parameters.AuthSuffix;
		AdminUser = $Parameters.AdminUser;
		AdminPassword = $Parameters.AdminPassword
		#XospClientId = $Parameters['ClientID-XospControl'];
		#XospClientSecret = $Parameters['ClientSecret-XospControl']
	}

	$TaskParamsPath = Join-Path $TargetPath "Tasks" "task-params.json"
	$TaskParameters | ConvertTo-Json -Depth 100 | Set-Content $TaskParamsPath
}

#########################################

Read-Host -Prompt "Press Enter to finish"