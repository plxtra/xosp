#Requires -PSEDition Core -Version 7
param (
	[String] $UserID,
	[String] $Type = "Operator",
	[String[]] $Features = @(),
	[String[]] $Entities = @(),
	[String[]] $Classes = @(),
	[String[]] $Feeds = @()
)

# This script registers a new User with Foundry

if (!(Test-Path "/tasks/init-params.ps1"))
{
	Write-Warning "Unable to find parameters. Did you run XOSP-Configure.ps1 first?"
	
	exit -1
}

# Execute the Shared Module script
. "/tasks/init-params.ps1"
. "/tasks/common.ps1"

$FoundryControl = "/app/foundry/Paritech.Foundry.Control.dll"

#########################################

$AdditionalArguments = @()

foreach ($Feed in $Feeds)
{
	$AdditionalArguments += @("-Feed", $Feed)
}

foreach ($Feature in $Features)
{
	$AdditionalArguments += @("-Feature", $Feature)
}

foreach ($Entity in $Entities)
{
	$EntityID = & dotnet $FoundryControl Entity Lookup XOSP $Entity -TopLevel -Id

	$AdditionalArguments += @("-Entity", $EntityID)
}

foreach ($EntityClass in $Classes)
{
	$EntityID = & dotnet $FoundryControl EntityClass Lookup XOSP $EntityClass -TopLevel

	$AdditionalArguments += @("-Class", $EntityID)
}

& dotnet $FoundryControl Identity Define XOSP Auth "User:$UserID" -Type $Type @AdditionalArguments | Out-Null
