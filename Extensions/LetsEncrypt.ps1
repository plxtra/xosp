#Requires -PSEDition Core -Version 7

using namespace System.Xml.Linq

class LetsEncryptInstance
{
	[bool] $Testing = $false
	[bool] $Interactive = $false
	[bool] $RegisterEmail = $false
	[int] $ListenPort = 80

	LetsEncryptInstance([PSObject] $Settings)
	{
		if ($null -ne $Settings.ListenPort)
		{
			$this.ListenPort = $Settings.ListenPort
		}

		if ($Settings.Testing -eq $true)
		{
			$this.Testing = $true
		}

		if ($Settings.Interactive -eq $true)
		{
			$this.Interactive = $true
		}

		if ($Settings.RegisterEmail -eq $true)
		{
			$this.RegisterEmail = $true
		}
	}

	Configure([string] $TargetPath, [PSObject] $Parameters)
	{
		if ($Parameters.RootDomainName.EndsWith("localhost"))
		{
			Write-Warning "To use LetsEncrypt, first modify your XOSP-Params.json file to specify your root domain, and rerun Configure"

			return
		}

		if ($Parameters.PublicHttpPort -ne 80)
		{
			Write-Warning "To use LetsEncrypt, XOSP must be using an internet-accessible port 80. Your current port is $($Parameters.PublicHttpPort)"

			return
		}

		Write-Host "================================================================================"
		Write-Host "To install the LetsEncrypt extension, the following steps must be taken:"
		Write-Host "- Public DNS exists for '$($Parameters.RootDomainName)'"
		Write-Host "- Public DNS exists for the subdomains: $($Parameters.SubDomains)"
		
		if ($Parameters.HttpPort -eq 80)
		{
			Write-Host "- Port 80 (HTTP) must be forwarded to the machine that will run XOSP-Install"
		}
		else
		{
			Write-Host "- Port 80 (HTTP) must be forwarded to port $($Parameters.HttpPort) on the machine that will run XOSP-Install"
		}
		
		Write-Host "================================================================================"
	}

	PreInstall([string] $TargetPath, [PSObject] $Parameters, [array] $ComposeArgs)
	{
		if ($Parameters.RootDomainName.EndsWith("localhost"))
		{
			return
		}

		Write-Host "Preparing LetsEncrypt..."

		# If the main XOSP nginx is running, we can skip starting our own
		$NginxStatus = & docker $ComposeArgs ps --no-trunc --format json nginx | ConvertTo-Json

		$RunTempServer = $null -eq $NginxStatus -or $NginxStatus.State -ne "running"

		$AdditionalArgs = @()

		if ($this.Testing)
		{
			$AdditionalArgs += "--test-cert"
		}

		if (-not $this.Interactive)
		{
			$AdditionalArgs += @("--non-interactive", "--agree-tos")
		}
		
		if ($this.RegisterEmail)
		{
			$AdditionalArgs += @("--eff-email", "--email", $Parameters.AdminEmail)
		}
		else
		{
			$AdditionalArgs += "--no-eff-email"
		}

		foreach ($Subdomain in $Parameters.SubDomains)
		{
			$AdditionalArgs += @("-d", "${Subdomain}.$($Parameters.RootDomainName)")
		}

		if ($RunTempServer)
		{
			$AltComposeArgs = @("compose", "--env-file", $(Join-Path $TargetPath $Parameters.DockerEnvFile), "--file", $(Join-Path $TargetPath "docker-compose.le-init.yml"))

			# First we start nginx, so certbot can issue our certificates
			& docker @AltComposeArgs up --no-recreate --wait nginx

			# Run certbot
			# - Use the local path within the docker container
			# - Use the root domain name as our certificate folder (/etc/letsencrypt/live/<root>/...)
			# - If install is being run again, don't refresh the certificates unless they're expiring
			# - ...Unless XOSP has added new domains, then expand the certificate to cover them
			# - Don't schedule auto-renewal, as we're running in a temporary container
			& docker @AltComposeArgs run --rm certbot certonly --webroot --webroot-path "/var/www/certbot" --cert-name $Parameters.RootDomainName --keep-until-expiring --expand --no-autorenew @AdditionalArgs
			
			& docker @AltComposeArgs down
		}
		else
		{
			# Use the certbot configured in our existing install
			& docker @ComposeArgs run --rm certbot certonly --webroot --webroot-path "/var/www/certbot" --cert-name $Parameters.RootDomainName --keep-until-expiring --expand --no-autorenew @AdditionalArgs

			# Reload the SSL certificates
			& docker @ComposeArgs exec nginx nginx -s reload
		}

		$SourcePath = Join-Path $PSScriptRoot "LetsEncrypt" "XOSP-Renew.ps1"

		Copy-Item -Path $SourcePath -Destination (Split-Path $TargetPath)
	}

	PostInstall([string] $TargetPath, [PSObject] $Parameters)
	{
		Write-Host "================================================================================"
		Write-Host "MANUAL STEP REQUIRED:"
		Write-Host "  For LetsEncrypt certificate renewal, a script has been prepared at:"
		Write-Host "    $(Join-Path (Split-Path $TargetPath) "XOSP-Renew.ps1")"
		Write-Host "  This script must be scheduled to run every ~90 days to ensure HTTPS remains valid."
	}

	Renew([string] $TargetPath, [PSObject] $Parameters, [array] $ComposeArgs)
	{
		$AdditionalArgs = @()

		if ($this.Testing)
		{
			$AdditionalArgs += "--test-cert"
		}

		# Run certbot
		# - Use the local path within the docker container
		# - Everything else will use the configuration in our SharedDataPath/certbot/conf folder
		& docker @ComposeArgs run --rm certbot renew --webroot --webroot-path "/var/www/certbot" @AdditionalArgs

		# Reload the SSL certificates
		& docker @ComposeArgs exec nginx nginx -s reload
	}

	[string[]] GetComposeFiles()
	{
		return @("docker-compose.le.yml")
	}
}

class LetsEncryptExtension
{
	LetsEncryptExtension()
	{
	}

	[string] $Name = "LetsEncrypt"

	[object] Create([PSObject] $Settings)
	{
		return [LetsEncryptInstance]::new($Settings)
	}
}

return [LetsEncryptExtension]::new()