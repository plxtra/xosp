#Requires -PSEDition Core -Version 7


#########################################

# Execute the Shared Module script
. "/tasks/init-params.ps1"
. "/tasks/common.ps1"

$SessionsControl = "/app/sessions/Paritech.Sessions.Control.dll"

#########################################

& dotnet $SessionsControl Pool Set XOSP Default | Out-Null

Write-Host '.' -NoNewline

& dotnet $SessionsControl Pool Set XOSP General -Sessions 1 -Connections 5 -Grace '00:00:04' -Resource | Out-Null

Write-Host '.'