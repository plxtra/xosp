param([PSObject] $Parameters)

$Defaults = @"
{
	// Environment Settings
	"Environment": "XOSP", // Environment name used for configuration files and logging
	"EnvironmentTag": "", // Tag used in realtime data. Empty string typically implies Production, but this is not required. eg: 'test' makes markets like 'ASX[Test]'
	"RootDomainName": "xosp.localhost", // We generate a wildcard certificate, so straight localhost is invalid as *.localhost won't be accepted by a browser (you can't wildcard a tld)

	// Docker Settings
	"RegistryUri": "", // For loading container images from a custom registry (eg: Amazon ECR). Needs a trailing slash
	"RegistryNamespace": "", // Namespace to append to the URI, if any
	"ComposeProject": "xosp", // The name for the docker compose project to group containers. Use for multiple installations on a single machine
	"DockerEnvFile": ".env", // The docker env file to pass to compose during installation, if you want to customise things
	"ImageTag": "0.91", // The tag for the XOSP images to pull
	"NonRootUID": 1654, // The Linux User ID used for non-root containers. Default in the .Net images is 1654 for 'app'

	// Host settings
	"SharedDataPath": "~/Plxtra/XOSP", // The local host path in which to store service data. If null, defaults to a host-specific path

	// Database Settings
	"DbServer": "postgres", // Use the PostgreSQL container in the docker-compose, or change to use an external server (eg: Amazon RDS)
	"DbUserSuffix": "", // Suffix for users when using an external (shared) database service
	"DatabaseSuffix": "", // Suffix for databases when using an external (shared) database service
	"DbSuperUser": "xosp", // Username for the PostgreSQL super-user
	"DbSuperPassword": "", // Blank/null to auto-generate something

	// Auth Settings
	"AuthSuffix": "", // Appended to any Resource Name and Scope value. eg: a suffix of XOSP means Prodigy-FixAPI -> ProdigyXOSP-FixAPI. Use for multiple installations with a single auth server
	"AdminUser": "XospAdmin", // Default User created by the system
	"AdminPassword": "xosp", // Default Password for the user created by the system
	"AdminEmail": "admin@xosp.localhost", // Registered email for password recovery. If null, defaults to admin @ the root domain name

	// Web Settings
	"HttpPort": 80, // The HTTP port to bind on the host machine
	"HttpsPort": 443, // The HTTPS port to bind to on the host machine
	"CertificateFile":"xosp", // What to call the SSL certificate. No extension - .pem/.key/.crt will be appended as necessary
	"GenerateCertificate": true, // Whether to create a self-signed certificate for the domain. False to leave certificate generation to the consumer

	// Market Settings
	"MarketCode": "XSX", // The code for the default market on the exchange. Defaults to XSX (XOSP Stock eXchange)
	"MarketShortCode": null, // The short code for the market in front-end applications. If null, defaults to MarketCode
	"MarketName": "XOSP Stock Exchange", // The long name for the default market on the exchange
	"MarketTimeZone": "Utc", // The IANA timezone for the market. Affects the 24 hour time period used for open/high/low/close values. If null defaults to the host's timezone, if available, otherwise Utc
	"MarketOperator": "XS", // The system code for the market operator
	"MarketOperatorName": "XOSP Registry Operator", // The descriptive name for the market operator
	"Currency": "AUD", // The currency used for trading. Must be listed in Config/Init/currencies.csv

	// Population Settings
	"AutoPopulateAccounts": 10, // The number of auto-generated accounts to prepare
	"AutoPopulateAccountTemplate":"D4", // .Net format string for generating account names from numbers

	"AutoPopulateSymbols": 10,
	"AutoPopulateSymbolsTemplate":"'XS'00", // .Net format string for generating account names from numbers

	"Extensions": []
}
"@ | ConvertFrom-Json -AsHashtable

$Defaults.PublicHttpPort = $Parameters.HttpPort ?? 80
$Defaults.PublicHttpsPort = $Parameters.HttpsPort ?? 443
$Defaults.AdminEmail = "admin@" + $Parameters.RootDomainName

# Setup some platform-specific defaults
if ($IsWindows)
{
	$Defaults.SharedDataPath = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)) "Plxtra" "XOSP"
}

# Determine the default timezone
$CurrentTimeZone = [TimeZoneInfo]::Local

if ($CurrentTimeZone.HasIanaId)
{
	$Defaults.MarketTimeZone = $CurrentTimeZone.Id;
}
else
{
	$IanaTimeZone = ""
	
	if ([TimeZoneInfo]::TryConvertWindowsIdToIanaId([TimeZoneInfo]::Local.Id, [ref] $IanaTimeZone))
	{
		$Defaults.MarketTimeZone = $IanaTimeZone;
	}	
}

return $Defaults