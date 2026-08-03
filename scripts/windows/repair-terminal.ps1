param(
  [string]$InstallDir = "C:\ai-deep-monitor"
)

$ErrorActionPreference = "Stop"
$helpers = Join-Path $PSScriptRoot "client-platform.ps1"
if (-not (Test-Path -LiteralPath $helpers -PathType Leaf)) {
  throw "client-platform.ps1 introuvable dans $PSScriptRoot"
}
. $helpers

if (-not (Test-Path -LiteralPath $InstallDir -PathType Container)) {
  throw "Installation introuvable: $InstallDir"
}

Write-Host "Installation/reparation du terminal hote Windows..." -ForegroundColor Cyan
Install-AiMonitorHostTerminalAgent -InstallDir $InstallDir -Required
Write-Host "Terminal hote operationnel: agent actif et liaison Docker validee." -ForegroundColor Green
