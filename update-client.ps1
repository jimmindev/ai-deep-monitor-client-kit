param(
  [string]$InstallDir = "C:\ai-deep-monitor",
  [Parameter(Mandatory = $true)]
  [string]$AppVersion,
  [switch]$SkipDockerLogin,
  [switch]$NoStart
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

if (-not (Test-Path -LiteralPath $composePath)) {
  throw "Compose introuvable: $composePath. Lance d'abord install-client.ps1."
}
if (-not (Test-Path -LiteralPath $envPath)) {
  throw ".env introuvable: $envPath. Lance d'abord install-client.ps1."
}

$backupPath = Join-Path $InstallDir (".env.backup-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
Copy-Item -LiteralPath $envPath -Destination $backupPath -Force

$content = Get-Content -LiteralPath $envPath -Raw
if ($content -match "(?m)^APP_VERSION=") {
  $content = $content -replace "(?m)^APP_VERSION=.*$", "APP_VERSION=$AppVersion"
} else {
  $content = "APP_VERSION=$AppVersion`r`n" + $content
}
Set-Content -LiteralPath $envPath -Value $content -Encoding UTF8

Write-Host "Version cible: $AppVersion"
Write-Host "Backup .env: $backupPath"

if ($NoStart) {
  Write-Host "NoStart actif: version mise a jour sans lancement Docker."
  exit 0
}

Require-Command "docker"
docker version | Out-Null
docker compose version | Out-Null

if (-not $SkipDockerLogin) {
  Write-Host "Connexion au registry prive GHCR."
  $githubUser = Read-Host "Utilisateur GitHub"
  $secureToken = Read-Host "Token GitHub avec read:packages" -AsSecureString
  $tokenPtr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureToken)
  try {
    $plainToken = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($tokenPtr)
    $plainToken | docker login ghcr.io -u $githubUser --password-stdin
  } finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($tokenPtr)
  }
}

docker compose -f $composePath --env-file $envPath pull
docker compose -f $composePath --env-file $envPath up -d
docker compose -f $composePath --env-file $envPath ps

Write-Host ""
Write-Host "Mise a jour terminee vers $AppVersion."
