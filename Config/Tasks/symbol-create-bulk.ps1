#Requires -PSEDition Core -Version 7
param (
	[String] $MarketCode,
	[Int32] $StartFrom,
	[Int32] $Count,
	[String] $SymbolTemplate,
	[String] $NameTemplate = "Default Security {0}",
	[String] $Currency = "AUD"
)

# This script registers a series of Symbols with the XOSP system

#########################################

$SymbolCodes = $StartFrom..($StartFrom + $Count - 1) | ForEach-Object -ThrottleLimit 4 -Parallel {
	$SymbolCode = $_.ToString($using:SymbolTemplate)
	$SymbolName = [String]::Format($using:NameTemplate, $SymbolCode)
	
	& /tasks/symbol-create.ps1 -MarketCode $using:MarketCode -SymbolCode $SymbolCode -SymbolName $SymbolName -Currency $using:Currency
	
	if ($global:LASTEXITCODE -lt 0)
	{
		exit -1
	}
	
	# We output the generated symbol codes, so the calling script can capture them for use
	return "${SymbolCode}.${using:MarketCode}"
}

$SymbolCodes | Out-String -Stream