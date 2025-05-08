#Requires -PSEDition Core -Version 7

using namespace System.Xml.Linq

class RecordingsInstance
{
	[string] $Market
	[string[]] $Dates

	static [string] $RootUrl = "https://plxtra.s3.ap-southeast-2.amazonaws.com/recordings/"

	RecordingsInstance([PSObject] $Settings)
	{
		# TODO: Parse settings for this extension - market, dates, etc
		$this.Market = $Settings.Market
		$this.Dates = $Settings.Dates
	}

	Configure([string] $TargetPath, [PSObject] $Parameters)
	{
		$RecordingPath = Join-Path $Parameters.SharedDataPath "Zenith" "Temporal" "Market" $this.Market

		Write-Host "Configuring recordings for $($this.Market)..."

		# Download the temporal market recordings to the Shared Data folder
		$BaseUri = [RecordingsInstance]::RootUrl + $this.Market

		$Recordings = @()

		if (-not (Test-Path $RecordingPath))
		{
			New-Item -Path $RecordingPath -ItemType Directory > $null
		}

		foreach ($Date in $this.Dates)
		{
			# Download and read the metadata
			$SourceUri = $BaseUri + "/$Date.tar.json"
			$OutputPath = Join-Path $RecordingPath "$Date.tar.json"

			if (-not (Test-Path $OutputPath))
			{
				$TempPath = Join-Path $RecordingPath "$Date.tar.json.part"

				Write-Host "`tDownloading metadata from $SourceUri..."

				Invoke-WebRequest -Uri $SourceUri -OutFile $TempPath -Resume

				# Once the download is complete, we can then rename it to the final name
				Move-Item -Path $TempPath -Destination $OutputPath
			}

			$DateMetadata = Get-Content -Path $OutputPath -Raw | ConvertFrom-Json

			$Recording = [XElement]::new(
				"add",
				[XAttribute]::new("Date", $DateMetadata.Date)
			)

			if ($DateMetadata.From)
			{
				$Recording.Add([XAttribute]::new("From", $DateMetadata.From))
			}

			if ($DateMetadata.TZ)
			{
				$Recording.Add([XAttribute]::new("TZ", $DateMetadata.TZ))
			}

			if ($DateMetadata.Duration)
			{
				$Recording.Add([XAttribute]::new("Duration", $DateMetadata.Duration))
			}

			if ($DateMetadata.Offset)
			{
				$Recording.Add([XAttribute]::new("Offset", $DateMetadata.Offset))
			}

			$Recordings += $Recording

			# Check and download the tar file
			$SourceUri = $BaseUri + "/$Date.tar"
			$OutputPath = Join-Path $RecordingPath "$Date.tar"

			if (-not (Test-Path $OutputPath))
			{
				$TempPath = Join-Path $RecordingPath "$Date.tar.part"

				Write-Host "`tDownloading recording from $SourceUri..."

				# Download to a temp file, resuming if necessary
				Invoke-WebRequest -Uri $SourceUri -OutFile $TempPath -Resume

				# Once the download is complete, we can then rename it to the final name
				Move-Item -Path $TempPath -Destination $OutputPath
			}
		}

		# Update the Zenith service configuration
		$ConfigFilePath = Join-Path $TargetPath "Zenith" "Paritech.Zenith.Service.dll.config"

		$ConfigBody = [XDocument]::Load($ConfigFilePath) # This does reset the whitespace, but adding [LoadOptions]::PreserveWhitespace means the new Component doesn't get formatted at all

		$Components = $ConfigBody.Root.Element("Paritech.Zenith").Element("Feed").Element("Components")

		$CurrentComponent = [XElement]::new(
			"add",
			[XAttribute]::new("Type", "Paritech.Zenith.Feed.Temporal.ScriptedMarketPlaybackProvider, Paritech.Zenith.Feed.Temporal"),
			[XAttribute]::new("Market", $this.Market),
			[XAttribute]::new("OutputMarket", $this.Market + "[Sample]"),
			[XComment]::new("Added by the XOSP Recordings extension"),
			[XElement]::new("Recordings", $Recordings)
			)

		$Components.Add($CurrentComponent)

		$ConfigBody.Save($ConfigFilePath, [SaveOptions]::None)
	}

	[string[]] GetMarkets()
	{
		return @()
	}

	[string[]] GetSampleMarkets()
	{
		return @($this.Market)
	}
}

class RecordingsExtension
{
	RecordingsExtension()
	{
	}

	[string] $Name = "Recordings"

	[object] Create([PSObject] $Settings)
	{
		return [RecordingsInstance]::new($Settings)
	}
}

return [RecordingsExtension]::new()