param(
  [string]$InstallDir = "C:\ai-deep-monitor",
  [string]$AppVersion = "v0.1.0",
  [string]$GithubOwner = "jimmindev",
  [int]$FrontendPort = 80,
  [int]$ApiPort = 8000,
  [string]$CorsOrigins = "",
  [switch]$SkipDockerLogin,
  [switch]$NoStart
)

$ErrorActionPreference = "Stop"

function New-Secret {
  param([int]$Bytes = 24)
  $buffer = New-Object byte[] $Bytes
  $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
  try {
    $rng.GetBytes($buffer)
  } finally {
    $rng.Dispose()
  }
  return ([Convert]::ToBase64String($buffer)).TrimEnd("=").Replace("+", "A").Replace("/", "B")
}

function Require-Command {
  param([string]$Name)
  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    throw "Commande introuvable: $Name"
  }
}

if (-not $CorsOrigins) {
  if ($FrontendPort -eq 80) {
    $CorsOrigins = "http://localhost"
  } else {
    $CorsOrigins = "http://localhost:$FrontendPort"
  }
}

$installPath = New-Item -ItemType Directory -Force -Path $InstallDir
$composeSource = Join-Path $PSScriptRoot "docker-compose.release.yml"
if (-not (Test-Path -LiteralPath $composeSource)) {
  throw "docker-compose.release.yml introuvable dans $PSScriptRoot"
}

$composeTarget = Join-Path $installPath.FullName "docker-compose.release.yml"
$envTarget = Join-Path $installPath.FullName ".env"

Copy-Item -LiteralPath $composeSource -Destination $composeTarget -Force

if (-not (Test-Path -LiteralPath $envTarget)) {
  $mysqlRootPassword = New-Secret
  $mysqlPassword = New-Secret
  $envContent = @"
GITHUB_OWNER=$GithubOwner
APP_VERSION=$AppVersion

MYSQL_ROOT_PASSWORD=$mysqlRootPassword
MYSQL_DATABASE=ai_monitor_prod
MYSQL_USER=ai_user
MYSQL_PASSWORD=$mysqlPassword

CORS_ORIGINS=$CorsOrigins

FRONTEND_PORT=$FrontendPort
API_PORT=$ApiPort
"@
  Set-Content -LiteralPath $envTarget -Value $envContent -Encoding UTF8
  Write-Host "Fichier .env cree avec mots de passe generes: $envTarget"
} else {
  Write-Host "Fichier .env deja present, il est conserve: $envTarget"
}

if ($NoStart) {
  Write-Host "NoStart actif: installation preparee sans lancement Docker."
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

docker compose -f $composeTarget --env-file $envTarget pull
docker compose -f $composeTarget --env-file $envTarget up -d

Write-Host ""
Write-Host "Installation terminee."
Write-Host "Frontend: http://localhost:$FrontendPort"
Write-Host "API health: http://localhost:$ApiPort/health"
