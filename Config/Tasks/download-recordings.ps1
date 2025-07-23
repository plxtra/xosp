#Requires -PSEDition Core -Version 7
param(
	[string] $RootUrl = "https://plxtra.s3.ap-southeast-2.amazonaws.com/recordings/",
	[string] $Market,
	[string[]] $Dates
)

$RecordingPath = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)) "Paritech" "Zenith" "Temporal" "Market" $Market

# Download the temporal market recordings to the Shared Data folder
$BaseUri = $RootUrl + $Market

if (-not (Test-Path $RecordingPath))
{
	New-Item -Path $RecordingPath -ItemType Directory > $null
}

Write-Host "Saving recordings to $RecordingPath"

foreach ($Date in $Dates)
{
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