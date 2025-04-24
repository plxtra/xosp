# $DockerHost variable

# Environment Settings
$Parameters.Environment = "XOSP" # Environment name used for configuration files and logging
$Parameters.EnvironmentTag = "" # Tag used in realtime data. Empty string typically implies Production, but this is not required. eg: 'test' makes markets like 'ASX[Test]'
$Parameters.RootDomainName = "xosp.localhost" # We generate a wildcard certificate, so straight localhost is invalid as *.localhost won't be accepted by a browser (you can't wildcard a tld)

# Docker Settings
$Parameters.ContainerSuffix = "-xosp" # A suffix to append to all container names. eg: '-xosp' means 'postgres' -> 'postgres-xosp'. Use for multiple installations on a single machine
$Parameters.RegistryUri = "public.ecr.aws/a5o2c1d0/" # For loading container images from a custom registry (eg: Amazon ECR). Needs a trailing slash

# aws ecr get-login-password --region ap-southeast-2 | docker login --username AWS --password-stdin 396377695266.dkr.ecr.ap-southeast-2.amazonaws.com

# Database Settings
$Parameters.DbServer = "postgres" # Use the PostgreSQL container in the docker-compose, or change to use an external server (eg: Amazon RDS)
$Parameters.DbUserSuffix = "" # Suffix for users when using an external (shared) database service
$Parameters.DatabaseSuffix = "" # Suffix for databases when using an external (shared) database service
$Parameters.DbSuperUser = "xosp" # Username for the PostgreSQL super-user
$Parameters.DbSuperPassword = "" # Blank/null to auto-generate something

# Auth Settings
$Parameters.AuthSuffix = "" # Appended to any Resource Name and Scope value. eg: a suffix of XOSP means Prodigy-FixAPI -> ProdigyXOSP-FixAPI. Use for multiple installations with a single auth server
$Parameters.AdminUser = "XospAdmin" # Default User created by the system
$Parameters.AdminPassword = "xosp" # Default Password for the user created by the system
$Parameters.AdminEmail = "admin@xosp.localhost" # Registered email for password recovery

# Web Settings
# $Parameters.SslPort = ? # The port to bind to on the host machine. Default to 443 on Linux, 8043 on Windows and MacOS
$Parameters.CertificateFile = "xosp" # What to call the SSL certificate. No extension - .pem and .key will be appended as necessary

# Market Settings
$Parameters.MarketCode = "XSX" # The code for the default market on the exchange. Defaults to XSX (XOSP Stock Exchange)
$Parameters.MarketShortCode = "XS" # The short code for the market in front-end applications. If null, defaults to MarketCode
$Parameters.MarketName = "XOSP Stock Exchange" # The long name for the default market on the exchange
# $Parameters.MarketTimeZone = "Utc" # The IANA timezone for the market. Affects the 24 hour time period used for open/high/low/close values. Defaults to the host's timezone, if available
$Parameters.MarketOperator = "XS" # The system code for the market operator
$Parameters.MarketOperatorName = "XOSP Registry Operator" # The descriptive name for the market operator
$Parameters.Currency = "AUD" # The currency used for trading. Must be listed in Config/Init/currencies.csv

# Population Settings
$AutoPopulateAccounts = 10 # The number of auto-generated accounts to prepare
$AutoPopulateAccountTemplate = "D4" # .Net format string for generating account names from numbers

$AutoPopulateSymbols = 10
$AutoPopulateSymbolsTemplate = "'XS'00" # .Net format string for generating account names from numbers

$GenerateCertificate = $true # Whether to create a self-signed certificate for the domain. False to leave certificate generation to the consumer