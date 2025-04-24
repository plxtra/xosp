# Script to be included via . for supplying initial default values
$GenerateCertificate = $true # Whether to create a self-signed certificate for the domain. False to leave certificate generation to the consumer

$AutoPopulateAccounts = 10; # The number of auto-generated accounts to prepare
$AutoPopulateAccountTemplate = "D4"; # .Net format string for generating account names from numbers

$AutoPopulateSymbols = 10;
$AutoPopulateSymbolsTemplate = "'XS'00"; # .Net format string for generating symbols names from numbers

$Parameters = @{
	# Environment Settings
	EnvironmentTag = ""; # Empty string typically implies Production, but this is not required. eg: 'test' makes markets like 'ASX[Test]'
	RootDomainName = "localhost"; # We generate a wildcard certificate, so straight localhost is invalid as *.localhost won't be accepted by a browser (you can't wildcard a tld)
	# Docker Settings
	ComposeProject = "xosp"; # The name for the docker compose project to group containers. Use for multiple installations on a single machine
	RegistryUri = ""; # For loading container images from a custom registry (eg: Amazon ECR)
	ForwardPorts = $false; # Whether to include the port forwarding
	# Database Settings
	DbServer = "postgres"; # Server hostname. Use the PostgreSQL container in the docker-compose, or change to use an external server (eg: Amazon RDS)
	DbUserSuffix = ""; # Suffix for service users when using an external (shared) database service
	DatabaseSuffix = ""; # Suffix for service databases when using an external (shared) database service
	DbSuperUser = "xosp"; # Username for the PostgreSQL super-user
	DbSuperPassword = ""; # Blank/null to auto-generate something
	# Auth Settings
	AuthSuffix = ""; # Appended to any Resource Name and Scope value. eg: a suffix of XOSP means Prodigy-FixAPI -> ProdigyXOSP-FixAPI. Use for multiple installations with a single auth server
	AdminUser = "XospAdmin"; # No initial password, requires being set on the first login
	AdminPassword = "xosp"; # Default Password for the user created by the system
	AdminEmail = "admin@xosp.localhost"; # Registered email for password recovery
	# Web Settings
	SslPort = 443; # The port to bind to on the host machine. Default to 443 on Linux, 8043 on Windows and MacOS
	CertificateFile = "xosp"; # What to call the SSL certificate. No extension - .pem and .key will be appended as necessary
	# Market Settings
	MarketCode = "XSX"; # The code for the default market on the exchange. Defaults to XSX (XOSP Stock Exchange)
	MarketShortCode = $null; # The short code for the market in front-end applications. If null, defaults to MarketCode
	MarketName = "XOSP Stock Exchange"; # The long name for the default market on the exchange
	MarketTimeZone = "Utc"; # The IANA timezone for the market. Affects the 24 hour time period used for open/high/low/close values. Defaults to the host's timezone, if available
	MarketOperator = "XS"; # The system code for the market operator
	MarketOperatorName = "XOSP Registry Operator"; # The descriptive name for the market operator
	Currency = "AUD" # The currency used for trading. Must be listed in Config/Init/currencies.csv
}