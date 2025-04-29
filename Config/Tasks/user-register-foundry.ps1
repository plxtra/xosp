#Requires -PSEDition Core -Version 7
param (
	[string] $UserID,
	[string] $Type = "Operator",
	[string[]] $Features = @(),
	[string[]] $Entities = @(),
	[string[]] $Classes = @(),
	[string[]] $Feeds = @()
)

# This script registers a new User with Foundry

if (!(Test-Path "/tasks/task-params.json"))
{
	Write-Warning "Unable to find parameters. Did you run XOSP-Configure.ps1 first?"
	
	exit -1
}

# Execute the shared tasks code
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
