#Requires -PSEDition Core -Version 7

if (!(Test-Path "XOSP-Params.ps1"))
{
	Write-Warning "Unable to find parameters. Ensure XOSP-Params.ps1 exists"
	
	exit
}

$RootPath = Get-Location
$SourcePath = Join-Path $RootPath Config # Where to find the configuration source files
$TargetPath = Join-Path $RootPath Docker # Where to output the prepared configurations

# Execute our various sub-scripts. Dot sourcing to share the execution context and inherit any variables
. (Join-Path $SourcePath "Init" "init-defaults.ps1")
. (Join-Path $PSScriptRoot "XOSP-Module.ps1")
. (Join-Path $PSScriptRoot "XOSP-Params.ps1")

# Apply any transformations we need
PostParameters

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
	Write-Host "Could not connect to Docker Engine. Please ensure Docker Engine is started and running."

	exit
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
# $Databases populated from XOSP-Module.ps1

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
	
	foreach ($Database in $Databases.GetEnumerator() | Sort-Object)
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

# These files we perform ${} replacement on
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

if ($GenerateCertificate -eq $true)
{
	$CertificateFile = Join-Path $TargetPath $Parameters.CertificateFile
	
	if (!(Test-Path "$CertificateFile.pfx"))
	{	
		Write-Host "Generating Certificate '$CertificateFile'..."
		
		$TargetFile = Join-Path $TargetPath $CertificateFile
		
		# Generate self-signed certificate
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
		
		$Extensions = [System.Collections.Generic.List[System.Security.Cryptography.X509Certificates.X509Extension]]::new()
		$Extensions.Add([System.Security.Cryptography.X509Certificates.X509BasicConstraintsExtension]::new($false, $false, 0, $false))
		$Extensions.Add([System.Security.Cryptography.X509Certificates.X509KeyUsageExtension]::new($KeyUsages, $false))
		$Extensions.Add([System.Security.Cryptography.X509Certificates.X509SubjectKeyIdentifierExtension]::new($CertRequest.PublicKey, $false))
		$Extensions.Add([System.Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension]::new($EnhancedKeyUsages, $false))
		$Extensions.Add($AltNames.Build($false))
		
		foreach ($Extension in $Extensions)
		{
			$CertRequest.CertificateExtensions.Add($Extension)
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
		$CertificateFormat = [System.Security.Cryptography.X509Certificates.X509ContentType]::Pfx
		if ($Passphrase)
		{
			$RawBytes = $Certificate.Export($CertificateFormat, $Passphrase)
		}
		else
		{
			$RawBytes = $Certificate.Export($CertificateFormat)
		}
		
		try
		{
			[System.IO.File]::WriteAllBytes("$CertificateFile.pfx", $RawBytes)
		}
		finally
		{
			[Array]::Clear($RawBytes, 0, $RawBytes.Length)
		}
		
		$RawString = $Certificate.ExportCertificatePem()
		[System.IO.File]::WriteAllText("$CertificateFile.crt", $RawString)
		
		$RawString = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($Certificate).ExportRSAPrivateKeyPem()
		[System.IO.File]::WriteAllText("$CertificateFile.key", $RawString)
	}
}

#########################################

Write-Host "Preparing Docker Compose files..."

if ($true)
{
	# Copy the base docker-compose file(s)
	Copy-Relative -SourcePath (Join-Path $SourcePath "Docker") -TargetPath $TargetPath -Include @("*.yml")
	
	# Prepare the environment file
	$SourceFile = Join-Path $SourcePath "Docker" ".env"
	$TargetFile = Join-Path $TargetPath $DockerEnvironmentFile
	
	Copy-WithReplace $SourceFile $TargetFile $Parameters	
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
	$TargetFile = Join-Path $DbTargetPath "credentials"
	
	$OutputFile = [System.IO.File]::CreateText($TargetFile)
	$OutputFile.NewLine = "`n" # Needs the Unix newline, as it'll be loaded by a shell script

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
	Copy-Item "XOSP-Params.ps1" (Join-Path $TargetPath "Init" "init-params.ps1")

	# Generate the task parameters file, which will get loaded by various administrative task scripts
	$TargetFile = Join-Path $TargetPath "Tasks" "init-params.ps1"
	
	$OutputFile = [System.IO.File]::CreateText($TargetFile)

	try
	{
		$OutputFile.WriteLine("`$UsingFoundry = `$false");
		$OutputFile.WriteLine()
		$OutputFile.WriteLine("`$TokenService = 'https://auth.$($Parameters.RootUri)'");
		$OutputFile.WriteLine("`$AuthSuffix = '$($Parameters.AuthSuffix)'");
		$OutputFile.WriteLine()
		
		$XospClientId = $Parameters['ClientID-XospControl']
		$XospClientSecret = $Parameters['ClientSecret-XospControl']		
		$OutputFile.WriteLine("`$XospClientId = '$XospClientId'");
		$OutputFile.WriteLine("`$XospClientSecret = '$XospClientSecret'");
		$OutputFile.Close()
	}
	finally
	{
		$OutputFile.Dispose()
	}
}

Read-Host -Prompt "Press Enter to finish"