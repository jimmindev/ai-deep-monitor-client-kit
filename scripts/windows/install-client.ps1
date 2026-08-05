param(
  [string]$InstallDir = "C:\ai-deep-monitor",
  [string]$AppVersion = "v0.1.17",
  [string]$GithubOwner = "jimmindev",
  [int]$FrontendPort = 80,
  [int]$ApiPort = 8000,
  [string]$CorsOrigins = "",
  [switch]$SkipDockerLogin,
  [switch]$StrictPorts,
  [switch]$NoStart
)

$ErrorActionPreference = "Stop"
$kitRoot = $PSScriptRoot
$repositoryRoot = Join-Path $PSScriptRoot "..\.."
if (Test-Path -LiteralPath (Join-Path $repositoryRoot "AI-Deep-Monitor.cmd")) {
  $kitRoot = (Resolve-Path -LiteralPath $repositoryRoot).Path
}

function Resolve-KitSource {
  param([string]$Name)
  $candidates = @(
    (Join-Path $PSScriptRoot $Name),
    (Join-Path $PSScriptRoot "..\linux\$Name"),
    (Join-Path $kitRoot $Name),
    (Join-Path $kitRoot "deploy\$Name")
  )
  if ($Name -eq "README_CLIENT.md") {
    $candidates += Join-Path $kitRoot "docs\installation.md"
  }
  foreach ($candidate in $candidates) {
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
      return (Resolve-Path -LiteralPath $candidate).Path
    }
  }
  return $null
}

$platformHelpers = Join-Path $PSScriptRoot "client-platform.ps1"
if (-not (Test-Path -LiteralPath $platformHelpers)) {
  throw "client-platform.ps1 introuvable dans $PSScriptRoot"
}
. $platformHelpers

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

function Get-PortComposeProjects {
  param([int]$Port)
  if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { return @() }
  try {
    return @(
      & docker ps `
        --filter "publish=$Port" `
        --format '{{.Label "com.docker.compose.project"}}' 2>$null |
        Where-Object { $_ } |
        Sort-Object -Unique
    )
  } catch {
    return @()
  }
}

function Test-PortAvailableForProject {
  param(
    [int]$Port,
    [string]$ProjectName
  )
  if (Test-PortAvailable -Port $Port) { return $true }
  return $ProjectName -in (Get-PortComposeProjects -Port $Port)
}

function Get-RuntimePort {
  param(
    [int]$PreferredPort,
    [string]$ProjectName,
    [int[]]$FallbackPorts = @(),
    [int[]]$ExcludedPorts = @(),
    [switch]$Strict
  )
  if (
    $PreferredPort -notin $ExcludedPorts -and
    (Test-PortAvailableForProject -Port $PreferredPort -ProjectName $ProjectName)
  ) {
    return $PreferredPort
  }
  if ($Strict) {
    throw "Le port $PreferredPort est deja utilise par un autre service."
  }
  foreach ($candidate in $FallbackPorts) {
    if (
      $candidate -notin $ExcludedPorts -and
      (Test-PortAvailableForProject -Port $candidate -ProjectName $ProjectName)
    ) {
      return $candidate
    }
  }
  $searchStart = if ($FallbackPorts.Count -gt 0) {
    [Math]::Max(($FallbackPorts | Measure-Object -Maximum).Maximum + 1, $PreferredPort + 1)
  } else {
    $PreferredPort + 1
  }
  return Get-AvailablePort -PreferredPort $searchStart -ExcludedPorts $ExcludedPorts
}

function Show-StartupDiagnostics {
  param(
    [string]$ComposePath,
    [string]$EnvPath
  )
  Write-Warning "Le demarrage Docker a echoue. Etat des services:"
  & docker compose -f $ComposePath --env-file $EnvPath ps -a 2>$null
  foreach ($service in @("mysql", "sandbox", "ollama", "ollama-models", "api", "collector")) {
    Write-Host ""
    Write-Host "===== $service ====="
    & docker compose -f $ComposePath --env-file $EnvPath logs --tail=100 $service 2>$null
  }
}

function Wait-ForHealthyContainer {
  param(
    [string]$ContainerName,
    [int]$TimeoutSeconds = 300
  )
  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  while ((Get-Date) -lt $deadline) {
    $rawState = & docker inspect `
      --format "{{.State.Status}}|{{if .State.Health}}{{.State.Health.Status}}{{end}}" `
      $ContainerName 2>$null
    $state = if ($rawState) { ([string]$rawState).Trim() } else { "" }
    if ($state -eq "running|healthy" -or $state -eq "running|") { return $true }
    if ($state -match "^(exited|dead)\|") { return $false }
    Start-Sleep -Seconds 3
  }
  return $false
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
      "${ProjectName}_client_ollama_data",
      "${ProjectName}_client_sandbox_jobs"
    )
    $volumes = @(& docker volume ls --format "{{.Name}}" 2>$null | Where-Object { $_ -in $expectedNames })
    foreach ($containerName in @("ai-monitor-client-mysql", "ai-monitor-client-api", "ai-monitor-client-ollama")) {
      $containerRows = @(& docker ps -a --filter "name=^/${containerName}$" --format "{{.ID}}" 2>$null)
      if ($containerRows.Count -eq 0) { continue }
      $mounted = @(& docker inspect --format '{{range .Mounts}}{{if eq .Type "volume"}}{{.Name}}{{println}}{{end}}{{end}}' $containerRows[0] 2>$null)
      $volumes += $mounted | Where-Object { $_ -and $_ -match "client_(mysql_data|api_data|uploaded_mibs|generated_backups|ollama_data|sandbox_jobs)$" }
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

function Remove-DotEnvValue {
  param(
    [string]$Path,
    [string]$Key
  )
  if (-not (Test-Path -LiteralPath $Path)) { return }
  $pattern = "^$([regex]::Escape($Key))="
  $content = @(Get-Content -LiteralPath $Path | Where-Object { $_ -notmatch $pattern })
  Set-Content -LiteralPath $Path -Value $content -Encoding UTF8
}

function Repair-AuthConfig {
  param([string]$Path)
  $values = Read-DotEnv -Path $Path
  $changed = $false
  $bootstrapPassword = $null

  if (-not $values["AUTH_SECRET_KEY"] -or $values["AUTH_SECRET_KEY"].Length -lt 32) {
    Write-DotEnvValue -Path $Path -Key "AUTH_SECRET_KEY" -Value (New-Secret -Bytes 48)
    $changed = $true
  }
  if (-not $values["AUTH_BOOTSTRAP_USERNAME"]) {
    Write-DotEnvValue -Path $Path -Key "AUTH_BOOTSTRAP_USERNAME" -Value "admin"
    $changed = $true
  }
  if (-not $values["AUTH_BOOTSTRAP_PASSWORD"]) {
    $bootstrapPassword = "Adm1-$(New-Secret -Bytes 18)"
    Write-DotEnvValue -Path $Path -Key "AUTH_BOOTSTRAP_PASSWORD" -Value $bootstrapPassword
    $changed = $true
  }

  $defaults = [ordered]@{
    AUTH_ACCESS_TOKEN_MINUTES = "15"
    AUTH_REFRESH_TOKEN_DAYS = "7"
    AUTH_MAX_FAILED_ATTEMPTS = "5"
    AUTH_LOCK_MINUTES = "15"
    AUTH_COOKIE_SECURE = "false"
    AUTH_COOKIE_SAMESITE = "lax"
    TELEMETRY_RAW_RETENTION_DAYS = "7"
    TELEMETRY_ROLLUP_RETENTION_DAYS = "365"
  }
  $values = Read-DotEnv -Path $Path
  foreach ($entry in $defaults.GetEnumerator()) {
    if (-not $values[$entry.Key]) {
      Write-DotEnvValue -Path $Path -Key $entry.Key -Value $entry.Value
      $changed = $true
    }
  }

  return @{
    Changed = $changed
    BootstrapPassword = $bootstrapPassword
  }
}

$installPath = New-Item -ItemType Directory -Force -Path $InstallDir
$composeSource = Resolve-KitSource "docker-compose.release.yml"
if (-not $composeSource) {
  throw "docker-compose.release.yml introuvable dans le kit"
}

$composeTarget = Join-Path $installPath.FullName "docker-compose.release.yml"
$envTarget = Join-Path $installPath.FullName ".env"
$projectName = ([IO.Path]::GetFileName($installPath.FullName)).ToLowerInvariant() -replace "[^a-z0-9_-]", ""
if (-not $projectName) { $projectName = "ai-deep-monitor" }

$kitFiles = @(
  "docker-compose.release.yml",
  "client-common.sh",
  "client-platform.ps1",
  "install-client.sh",
  "update-client.sh",
  "check-update.sh",
  "backup-client.sh",
  "backup-maintenance.sh",
  "restore-client.sh",
  "uninstall-client.sh",
  "repair-terminal.sh",
  "install-client.ps1",
  "update-client.ps1",
  "check-update.ps1",
  "backup-client.ps1",
  "backup-maintenance.ps1",
  "restore-client.ps1",
  "uninstall-client.ps1",
  "repair-terminal.ps1",
  "AI-Deep-Monitor.cmd",
  "ai-deep-monitor.sh",
  "ai-deep-monitor.ps1",
  "README_CLIENT.md"
)
foreach ($fileName in $kitFiles) {
  $source = Resolve-KitSource $fileName
  if ($source) {
    $target = Join-Path $installPath.FullName $fileName
    if ((Resolve-Path -LiteralPath $source).Path -ne $target) {
      Copy-Item -LiteralPath $source -Destination $target -Force
    }
  }
}
Remove-Item -LiteralPath (Join-Path $installPath.FullName "VERSION") -Force -ErrorAction SilentlyContinue
Sync-AiMonitorHostTerminalAgent -SourceRoot $kitRoot -InstallDir $installPath.FullName | Out-Null

$existingEnv = Test-Path -LiteralPath $envTarget
$bootstrapAdminPassword = $null
$dockerPlatform = if ($NoStart) {
  Get-AiMonitorHostPlatform
} else {
  Ensure-Docker
  Get-AiMonitorDockerPlatform
}
$existingVolumes = if ($NoStart) { @() } else { Get-ExistingDataVolumes -ProjectName $projectName }
if (-not $existingEnv -and $existingVolumes.Count -gt 0) {
  throw "Des volumes AI Deep Monitor existent deja mais .env est absent. Restaure l'ancien .env ou lance une desinstallation Full explicite; de nouveaux mots de passe rendraient MySQL inaccessible. Volumes: $($existingVolumes -join ', ')"
}

if ($existingEnv) {
  $existingValues = Read-DotEnv -Path $envTarget
  if ($existingValues["FRONTEND_PORT"]) { $FrontendPort = [int]$existingValues["FRONTEND_PORT"] }
  if ($existingValues["API_PORT"]) { $ApiPort = [int]$existingValues["API_PORT"] }
  if (-not $CorsOrigins -and $existingValues["CORS_ORIGINS"]) { $CorsOrigins = $existingValues["CORS_ORIGINS"] }
  Remove-DotEnvValue -Path $envTarget -Key "KIT_VERSION"
  Write-DotEnvValue -Path $envTarget -Key "DOCKER_PLATFORM" -Value $dockerPlatform
  Write-Host "Installation existante detectee: configuration et volumes conserves."
}

$requestedFrontendPort = $FrontendPort
$requestedApiPort = $ApiPort
$FrontendPort = Get-RuntimePort `
  -PreferredPort $FrontendPort `
  -ProjectName $projectName `
  -FallbackPorts @(8080) `
  -Strict:$StrictPorts
$ApiPort = Get-RuntimePort `
  -PreferredPort $ApiPort `
  -ProjectName $projectName `
  -FallbackPorts @(8001) `
  -ExcludedPorts @($FrontendPort) `
  -Strict:$StrictPorts

if ($FrontendPort -ne $requestedFrontendPort) {
  Write-Host "Port web $requestedFrontendPort occupe par un autre service; port $FrontendPort selectionne."
}
if ($ApiPort -ne $requestedApiPort) {
  Write-Host "Port API $requestedApiPort occupe par un autre service; port $ApiPort selectionne."
}

if (-not $CorsOrigins) {
  if ($FrontendPort -eq 80) { $CorsOrigins = "http://localhost" }
  else { $CorsOrigins = "http://localhost:$FrontendPort" }
}

if (-not $existingEnv) {
  $mysqlRootPassword = New-Secret
  $mysqlPassword = New-Secret
  $authSecret = New-Secret -Bytes 48
  $bootstrapAdminPassword = "Adm1-$(New-Secret -Bytes 18)"
  $envContent = @"
GITHUB_OWNER=$GithubOwner
GITHUB_REPOSITORY_NAME=ai-deep-monitor
APP_VERSION=$AppVersion
APP_CHANNEL=stable
DOCKER_PLATFORM=$dockerPlatform
UPDATE_CHECK_ENABLED=true
UPDATE_CHECK_CHANNEL=stable
UPDATE_CHECK_BRANCH=preprod
UPDATE_CHECK_USER=
UPDATE_CHECK_TOKEN=

OLLAMA_IMAGE=ollama/ollama:latest
OLLAMA_MODEL=llama3.2:3b
OLLAMA_FALLBACK_MODEL=llama3.2:1b
OLLAMA_TEMPERATURE=0.2
OLLAMA_NUM_PREDICT=512

MYSQL_ROOT_PASSWORD=$mysqlRootPassword
MYSQL_DATABASE=ai_monitor_prod
MYSQL_USER=ai_user
MYSQL_PASSWORD=$mysqlPassword

AUTH_SECRET_KEY=$authSecret
AUTH_BOOTSTRAP_USERNAME=admin
AUTH_BOOTSTRAP_PASSWORD=$bootstrapAdminPassword
AUTH_ACCESS_TOKEN_MINUTES=15
AUTH_REFRESH_TOKEN_DAYS=7
AUTH_MAX_FAILED_ATTEMPTS=5
AUTH_LOCK_MINUTES=15
AUTH_COOKIE_SECURE=false
AUTH_COOKIE_SAMESITE=lax

TELEMETRY_RAW_RETENTION_DAYS=7
TELEMETRY_ROLLUP_RETENTION_DAYS=365
HOST_TERMINAL_QUEUE_GID=10003
TERMINAL_SESSION_TTL_SECONDS=300
TERMINAL_POLICY_ADMIN_PASSWORD=ysitech1234

CORS_ORIGINS=$CorsOrigins

FRONTEND_PORT=$FrontendPort
API_PORT=$ApiPort
"@
  Set-Content -LiteralPath $envTarget -Value $envContent -Encoding UTF8
  Write-Host "Fichier .env cree avec mots de passe generes: $envTarget"
} else {
  Write-DotEnvValue -Path $envTarget -Key "FRONTEND_PORT" -Value "$FrontendPort"
  Write-DotEnvValue -Path $envTarget -Key "API_PORT" -Value "$ApiPort"
  $existingValues = Read-DotEnv -Path $envTarget
  if (-not $existingValues["OLLAMA_MODEL"] -or $existingValues["OLLAMA_MODEL"] -eq "llama3.1") {
    Write-DotEnvValue -Path $envTarget -Key "OLLAMA_MODEL" -Value "llama3.2:3b"
  }
  if (-not $existingValues["OLLAMA_FALLBACK_MODEL"] -or
      $existingValues["OLLAMA_FALLBACK_MODEL"] -in @("llama3.1", "llama3.2:3b")) {
    Write-DotEnvValue -Path $envTarget -Key "OLLAMA_FALLBACK_MODEL" -Value "llama3.2:1b"
    Write-Host "Configuration Ollama actualisee; les donnees existantes sont conservees."
  }
  $oldDefaultCors = if ($requestedFrontendPort -eq 80) {
    "http://localhost"
  } else {
    "http://localhost:$requestedFrontendPort"
  }
  if (-not $CorsOrigins -or $CorsOrigins -eq $oldDefaultCors) {
    $CorsOrigins = if ($FrontendPort -eq 80) {
      "http://localhost"
    } else {
      "http://localhost:$FrontendPort"
    }
    Write-DotEnvValue -Path $envTarget -Key "CORS_ORIGINS" -Value $CorsOrigins
  }
  Write-Host "Fichier .env deja present, il est conserve: $envTarget"
}

$authRepair = Repair-AuthConfig -Path $envTarget
$terminalValues = Read-DotEnv -Path $envTarget
if (-not $terminalValues["HOST_TERMINAL_QUEUE_GID"]) {
  Write-DotEnvValue -Path $envTarget -Key "HOST_TERMINAL_QUEUE_GID" -Value "10003"
}
if (-not $terminalValues["TERMINAL_SESSION_TTL_SECONDS"]) {
  Write-DotEnvValue -Path $envTarget -Key "TERMINAL_SESSION_TTL_SECONDS" -Value "300"
}
if (-not $terminalValues["TERMINAL_POLICY_ADMIN_PASSWORD"]) {
  Write-DotEnvValue -Path $envTarget -Key "TERMINAL_POLICY_ADMIN_PASSWORD" -Value "ysitech1234"
}
if ($authRepair.BootstrapPassword) {
  $bootstrapAdminPassword = $authRepair.BootstrapPassword
}
if ($authRepair.Changed -and $existingEnv) {
  Write-Host "Configuration d'authentification reparee; les donnees et comptes existants sont conserves."
}

if ($NoStart) {
  Write-Host "NoStart actif: installation preparee sans lancement Docker pour $dockerPlatform."
  if ($bootstrapAdminPassword) {
    Write-Host "Compte initial (seulement si aucun administrateur n'existe): admin / $bootstrapAdminPassword"
  }
  exit 0
}

Install-AiMonitorHostTerminalAgent -InstallDir $installPath.FullName -Required
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
if ($LASTEXITCODE -ne 0) {
  throw "Impossible de telecharger les images Docker."
}
docker compose -f $composeTarget --env-file $envTarget up -d
if ($LASTEXITCODE -ne 0) {
  Show-StartupDiagnostics -ComposePath $composeTarget -EnvPath $envTarget
  throw "Le stack Docker n'a pas demarre correctement. Consulte les journaux ci-dessus."
}
if (-not (Wait-ForHealthyContainer -ContainerName "ai-monitor-client-api")) {
  Show-StartupDiagnostics -ComposePath $composeTarget -EnvPath $envTarget
  throw "L'API n'est pas devenue operationnelle. Consulte les journaux ci-dessus."
}

Write-Host ""
Write-Host "Installation terminee."
Write-Host "Plateforme: $dockerPlatform"
$frontendUrl = if ($FrontendPort -eq 80) { "http://localhost" } else { "http://localhost:$FrontendPort" }
Write-Host "Frontend: $frontendUrl"
Write-Host "API health: http://localhost:$ApiPort/health"
if ($bootstrapAdminPassword) {
  Write-Host ""
  Write-Host "Compte initial, utilise uniquement si aucun administrateur n'existe deja:"
  Write-Host "Utilisateur: admin"
  Write-Host "Mot de passe: $bootstrapAdminPassword"
  Write-Host "Un compte existant conserve son mot de passe actuel."
}
