param([PSObject] $Parameters)

# Windows: C:\ProgramData\Plxtra\XOSP
# Linux/Mac: /usr/share/Plxtra/XOSP

$Parameters.SharedDataPath = Join-Path [Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData) "Plxtra" "XOSP"

return $Parameters