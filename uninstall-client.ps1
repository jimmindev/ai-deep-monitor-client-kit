param(
  [string]$InstallDir = "C:\ai-deep-monitor",
  [ValidateSet("Partial", "Full")]
  [string]$Mode = "Partial",
  [switch]$SkipBackup,
  [switch]$RemoveImages,
  [switch]$Yes
)

$ErrorActionPreference = "Stop"

function Require-Command {
  param([string]$Name)
  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    throw "Commande introuvable: $Name"
  }
}

$composePath = Join-Path $InstallDir "docker-compose.release.yml"
$envPath = Join-Path $InstallDir ".env"
if (-not (Test-Path -LiteralPath $composePath)) { throw "Compose introuvable: $composePath" }
if (-not (Test-Path -LiteralPath $envPath)) { throw ".env introuvable: $envPath" }

Require-Command "docker"
docker version | Out-Null
docker compose version | Out-Null
$composeArgs = @("compose", "-f", $composePath, "--env-file", $envPath)
& docker @composeArgs config --quiet

if ($Mode -eq "Partial") {
  Write-Host "Desinstallation partielle: conteneurs et reseau supprimes."
  Write-Host "Les volumes, images, sauvegardes et fichiers d'installation seront conserves."
} else {
  Write-Warning "Desinstallation COMPLETE: les volumes MySQL et applicatifs seront supprimes."
  Write-Host "Le dossier d'installation sera egalement supprime: $InstallDir"
}

if (-not $Yes) {
  $answer = Read-Host "Confirmer la desinstallation $Mode ? (o/N)"
  if ($answer -notin @("o", "O", "oui", "OUI", "y", "Y", "yes", "YES")) {
    Write-Host "Desinstallation annulee."
    exit 0
  }
}

if ($Mode -eq "Full" -and -not $SkipBackup) {
  $backupScript = Join-Path $PSScriptRoot "backup-client.ps1"
  if (-not (Test-Path -LiteralPath $backupScript)) {
    throw "backup-client.ps1 introuvable. Utilise -SkipBackup uniquement si la perte de donnees est acceptee."
  }
  Write-Host "Sauvegarde de securite avant suppression..."
  & $backupScript -InstallDir $InstallDir
}

if ($Mode -eq "Partial") {
  & docker @composeArgs down --remove-orphans
  Write-Host ""
  Write-Host "Desinstallation partielle terminee."
  Write-Host "Pour relancer: .\install-client.ps1 ou docker compose up -d depuis $InstallDir"
  exit 0
}

$downArgs = @("down", "--volumes", "--remove-orphans")
if ($RemoveImages) { $downArgs += @("--rmi", "all") }
& docker @composeArgs @downArgs

$resolvedInstallDir = (Resolve-Path -LiteralPath $InstallDir).Path
Set-Location $env:TEMP
Remove-Item -LiteralPath $resolvedInstallDir -Recurse -Force

Write-Host ""
Write-Host "Desinstallation complete terminee."
Write-Host "Les sauvegardes externes ont ete conservees."
if (-not $RemoveImages) {
  Write-Host "Les images Docker ont ete conservees. Ajoute -RemoveImages pour les supprimer lors d'une prochaine installation."
}
