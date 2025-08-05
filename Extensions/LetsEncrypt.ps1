#Requires -PSEDition Core -Version 7

using namespace System.Xml.Linq

class LetsEncryptInstance
{
	[bool] $Testing = $false
	[bool] $Interactive = $false
	[bool] $RegisterEmail = $false
	[bool] $AlwaysValidate = $false
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

		if ($Settings.AlwaysValidate -eq $true)
		{
			$this.AlwaysValidate = $true
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

		Write-Host "`tLetsEncrypt..."

		# We want to check if we have a certificate or not, so we can decide whether to do the relatively expensive task of starting/restarting nginx in init mode
		$HasCertificate = $false

		$VolumeName = "$($Parameters.ComposeProject)_shared"
		$RootDomainName = $Parameters.RootDomainName

		$VolumeStatus = & docker volume inspect --format json $VolumeName 2>$null | ConvertFrom-Json

		if ($null -ne $VolumeStatus -and $VolumeStatus.Count -eq 1)
		{
			# Volume exists, check if the certificate we expect is there. This also handles if the domain has changed
			# We should have, or will soon have, the runtime image, since we use it for the control tool
			$CertificateExists = & docker @ComposeArgs exec control-init pwsh -Command "Test-Path '/root/.local/share/Paritech/certbot/conf/live/$RootDomainName/fullchain.pem'"

			if ($CertificateExists -eq "True")
			{
				$HasCertificate = $true
			}
		}

		# Arguments we want to pass to Certbot
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

		if (-not $HasCertificate)
		{
			$AltComposeArgs = $ComposeArgs.Clone()

			# Rather than let certbot take over the port bindings, we leave that to nginx and link them with a shared volume for the www directory
			# This needs an alternate configuration from the normal nginx setup, as the default will fail to start without the ssl certs (which we haven't issued yet)
			$AltComposeArgs += @("--file", (Join-Path $TargetPath "docker-compose.le-init.yml"))

			#Write-Host $AltComposeArgs

			# For whatever reason, Docker won't create sub-folder volume binds if the folder doesn't exist,
			# so we need to create a container that uses the shared volume (to create the volume) and then make the directories
			& docker @AltComposeArgs create --force-recreate nginx
			& docker @ComposeArgs exec control-init bash -c "mkdir -p /root/.local/share/Paritech/certbot/conf /root/.local/share/Paritech/certbot/www"

			# If an nginx container exists, this will recreate and start it using the init configuration
			& docker @AltComposeArgs up --wait nginx

			# Run certbot
			# - Use the local path within the docker container
			# - Use the root domain name as our certificate folder (/etc/letsencrypt/live/<root>/...)
			# - If install is being run again, don't refresh the certificates unless they're expiring
			# - ...Unless XOSP has added new domains, then expand the certificate to cover them
			# - Don't schedule auto-renewal, as we're running in a temporary container
			& docker @AltComposeArgs run --rm certbot certonly --webroot --webroot-path "/var/www/certbot" --cert-name $Parameters.RootDomainName --keep-until-expiring --expand --no-autorenew @AdditionalArgs

			# We shouldn't need to do anything about the nginx container, as Docker Compose should identify the difference between configurations and recreate automatically later
			# FIX: Docker Compose on Linux doesn't seem to notice the configuration change, and needs a force recreate
			& docker @ComposeArgs create --force-recreate nginx
		}
		elseif ($this.AlwaysValidate)
		{
			# Use the certbot configured in our existing install
			& docker @ComposeArgs run --rm certbot certonly --webroot --webroot-path "/var/www/certbot" --cert-name $Parameters.RootDomainName --keep-until-expiring --expand --no-autorenew @AdditionalArgs

			# Reload the SSL certificates
			& docker @ComposeArgs exec nginx nginx -s reload
		}

		$CertificateExists = & docker @ComposeArgs exec control-init bash -c "chmod -R a+rX /root/.local/share/Paritech/certbot/conf/live /root/.local/share/Paritech/certbot/conf/archive"

		# Final step, ensure the renew script is copied to the startup folder
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