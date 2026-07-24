param(
  [string]$InstallDir = "C:\ai-deep-monitor",
  [string]$AppVersion = "v0.1.4",
  [string]$GithubOwner = "jimmindev",
  [int]$FrontendPort = 80,
  [int]$ApiPort = 8000,
  [string]$CorsOrigins = "",
  [switch]$SkipDockerLogin,
  [switch]$StrictPorts,
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

function Ensure-Docker {
  if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
      throw "Docker Desktop est absent et winget est indisponible. Installe Docker Desktop puis relance le script."
    }
    Write-Host "Docker Desktop est absent. Installation automatique via winget..."
    & winget install --id Docker.DockerDesktop -e --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) { throw "Echec de l'installation de Docker Desktop." }
    $dockerBin = Join-Path $env:ProgramFiles "Docker\Docker\resources\bin"
    if (Test-Path -LiteralPath $dockerBin) { $env:Path = "$dockerBin;$env:Path" }
  }

  Require-Command "docker"
  try {
    docker info | Out-Null
    docker compose version | Out-Null
    return
  } catch {
    $desktopPath = Join-Path $env:ProgramFiles "Docker\Docker\Docker Desktop.exe"
    if (Test-Path -LiteralPath $desktopPath) {
      Write-Host "Demarrage de Docker Desktop..."
      Start-Process -FilePath $desktopPath -WindowStyle Hidden
    }
  }

  $deadline = (Get-Date).AddMinutes(5)
  while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 3
    try {
      docker info | Out-Null
      docker compose version | Out-Null
      return
    } catch {}
  }
  throw "Docker Desktop est installe mais son moteur ne repond pas. Un redemarrage Windows peut etre necessaire."
}

function Read-DotEnv {
  param([string]$Path)
  $values = @{}
  if (-not (Test-Path -LiteralPath $Path)) { return $values }
  foreach ($line in Get-Content -LiteralPath $Path) {
    if ($line -match "^\s*#" -or $line -match "^\s*$") { continue }
    if ($line -match "^\s*([^=]+?)\s*=\s*(.*)\s*$") {
      $values[$Matches[1].Trim()] = $Matches[2].Trim().Trim('"').Trim("'")
    }
  }
  return $values
}

function Test-PortAvailable {
  param([int]$Port)
  $listener = $null
  try {
    $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Any, $Port)
    $listener.Server.ExclusiveAddressUse = $true
    $listener.Start()
    return $true
  } catch {
    return $false
  } finally {
    if ($listener) { $listener.Stop() }
  }
}

function Get-AvailablePort {
  param(
    [int]$PreferredPort,
    [int[]]$ExcludedPorts = @()
  )
  for ($port = $PreferredPort; $port -le [Math]::Min($PreferredPort + 200, 65535); $port++) {
    if ($port -notin $ExcludedPorts -and (Test-PortAvailable -Port $port)) { return $port }
  }
  throw "Aucun port disponible trouve a partir de $PreferredPort."
}

function Get-ExistingDataVolumes {
  param([string]$ProjectName)
  if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { return @() }
  try {
    $expectedNames = @(
      "${ProjectName}_client_mysql_data",
      "${ProjectName}_client_api_data",
      "${ProjectName}_client_uploaded_mibs",
      "${ProjectName}_client_generated_backups",
      "${ProjectName}_client_ollama_data"
    )
    $volumes = @(& docker volume ls --format "{{.Name}}" 2>$null | Where-Object { $_ -in $expectedNames })
    foreach ($containerName in @("ai-monitor-client-mysql", "ai-monitor-client-api", "ai-monitor-client-ollama")) {
      $containerRows = @(& docker ps -a --filter "name=^/${containerName}$" --format "{{.ID}}" 2>$null)
      if ($containerRows.Count -eq 0) { continue }
      $mounted = @(& docker inspect --format '{{range .Mounts}}{{if eq .Type "volume"}}{{.Name}}{{println}}{{end}}{{end}}' $containerRows[0] 2>$null)
      $volumes += $mounted | Where-Object { $_ -and $_ -match "client_(mysql_data|api_data|uploaded_mibs|generated_backups|ollama_data)$" }
    }
    return @($volumes | Sort-Object -Unique)
  } catch {
    return @()
  }
}

function Write-DotEnvValue {
  param(
    [string]$Path,
    [string]$Key,
    [string]$Value
  )
  $content = Get-Content -LiteralPath $Path -Raw
  if ($content -match "(?m)^$([regex]::Escape($Key))=") {
    $content = $content -replace "(?m)^$([regex]::Escape($Key))=.*$", "$Key=$Value"
  } else {
    $content = "$content`r`n$Key=$Value"
  }
  Set-Content -LiteralPath $Path -Value $content -Encoding UTF8
}

$installPath = New-Item -ItemType Directory -Force -Path $InstallDir
$composeSource = Join-Path $PSScriptRoot "docker-compose.release.yml"
if (-not (Test-Path -LiteralPath $composeSource)) {
  throw "docker-compose.release.yml introuvable dans $PSScriptRoot"
}

$composeTarget = Join-Path $installPath.FullName "docker-compose.release.yml"
$envTarget = Join-Path $installPath.FullName ".env"
$projectName = ([IO.Path]::GetFileName($installPath.FullName)).ToLowerInvariant() -replace "[^a-z0-9_-]", ""
if (-not $projectName) { $projectName = "ai-deep-monitor" }

$kitFiles = @(
  "docker-compose.release.yml",
  "client-common.sh",
  "install-client.sh",
  "update-client.sh",
  "check-update.sh",
  "backup-client.sh",
  "restore-client.sh",
  "uninstall-client.sh",
  "install-client.ps1",
  "update-client.ps1",
  "check-update.ps1",
  "backup-client.ps1",
  "restore-client.ps1",
  "uninstall-client.ps1",
  "README_CLIENT.md",
  "VERSION"
)
foreach ($fileName in $kitFiles) {
  $source = Join-Path $PSScriptRoot $fileName
  if (Test-Path -LiteralPath $source) {
    $target = Join-Path $installPath.FullName $fileName
    if ((Resolve-Path -LiteralPath $source).Path -ne $target) {
      Copy-Item -LiteralPath $source -Destination $target -Force
    }
  }
}

$existingEnv = Test-Path -LiteralPath $envTarget
$existingVolumes = Get-ExistingDataVolumes -ProjectName $projectName
if (-not $existingEnv -and $existingVolumes.Count -gt 0) {
  throw "Des volumes AI Deep Monitor existent deja mais .env est absent. Restaure l'ancien .env ou lance une desinstallation Full explicite; de nouveaux mots de passe rendraient MySQL inaccessible. Volumes: $($existingVolumes -join ', ')"
}

if ($existingEnv) {
  $existingValues = Read-DotEnv -Path $envTarget
  if ($existingValues["FRONTEND_PORT"]) { $FrontendPort = [int]$existingValues["FRONTEND_PORT"] }
  if ($existingValues["API_PORT"]) { $ApiPort = [int]$existingValues["API_PORT"] }
  if (-not $CorsOrigins -and $existingValues["CORS_ORIGINS"]) { $CorsOrigins = $existingValues["CORS_ORIGINS"] }
  Write-Host "Installation existante detectee: configuration et volumes conserves."
} else {
  if (-not $NoStart) {
    Ensure-Docker
  }
  if (-not (Test-PortAvailable -Port $FrontendPort)) {
    if ($StrictPorts) { throw "Le port frontend $FrontendPort est deja utilise." }
    $newPort = Get-AvailablePort -PreferredPort $FrontendPort
    Write-Host "Port frontend $FrontendPort occupe; port $newPort selectionne automatiquement."
    $FrontendPort = $newPort
  }
  if (-not (Test-PortAvailable -Port $ApiPort) -or $ApiPort -eq $FrontendPort) {
    if ($StrictPorts) { throw "Le port API $ApiPort est deja utilise." }
    $newPort = Get-AvailablePort -PreferredPort $ApiPort -ExcludedPorts @($FrontendPort)
    Write-Host "Port API $ApiPort indisponible; port $newPort selectionne automatiquement."
    $ApiPort = $newPort
  }
}

if (-not $CorsOrigins) {
  if ($FrontendPort -eq 80) { $CorsOrigins = "http://localhost" }
  else { $CorsOrigins = "http://localhost:$FrontendPort" }
}

if (-not $existingEnv) {
  $mysqlRootPassword = New-Secret
  $mysqlPassword = New-Secret
  $envContent = @"
GITHUB_OWNER=$GithubOwner
GITHUB_REPOSITORY_NAME=ai-deep-monitor
KIT_VERSION=v0.1.5
APP_VERSION=$AppVersion
APP_CHANNEL=stable
UPDATE_CHECK_ENABLED=true
UPDATE_CHECK_CHANNEL=stable
UPDATE_CHECK_BRANCH=preprod
UPDATE_CHECK_USER=
UPDATE_CHECK_TOKEN=

OLLAMA_IMAGE=ollama/ollama:latest
OLLAMA_MODEL=llama3.1
OLLAMA_TEMPERATURE=0.2
OLLAMA_NUM_PREDICT=512

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

Ensure-Docker
docker compose -f $composeTarget --env-file $envTarget config --quiet

if ($existingVolumes.Count -gt 0) {
  Write-Host "Volumes existants reutilises: $($existingVolumes -join ', ')"
}

if (-not $SkipDockerLogin) {
  Write-Host "Connexion au registry prive GHCR."
  $githubUser = Read-Host "Utilisateur GitHub"
  $secureToken = Read-Host "Token GitHub avec read:packages" -AsSecureString
  $tokenPtr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureToken)
  try {
    $plainToken = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($tokenPtr)
    $plainToken | docker login ghcr.io -u $githubUser --password-stdin
    Write-DotEnvValue -Path $envTarget -Key "UPDATE_CHECK_ENABLED" -Value "true"
    Write-DotEnvValue -Path $envTarget -Key "UPDATE_CHECK_USER" -Value $githubUser
    Write-DotEnvValue -Path $envTarget -Key "UPDATE_CHECK_TOKEN" -Value $plainToken
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
