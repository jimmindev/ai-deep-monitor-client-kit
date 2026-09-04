param(
  [string]$InstallDir = "C:\ai-deep-monitor",
  [string]$AppVersion = "",
  [switch]$SkipDockerLogin,
  [switch]$SkipBackup,
  [switch]$SkipAgentInstall,
  [ValidateSet("", "auto", "cpu", "nvidia")][string]$LlamaProfile = "",
  [switch]$RequireGpu,
  [switch]$RedetectLlamaRuntime,
  [switch]$NoStart,
  [switch]$Yes
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
$versionWasSpecified = [bool]$AppVersion

function Require-Command {
  param([string]$Name)
  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    throw "Commande introuvable: $Name"
  }
}

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

function Read-DotEnv {
  param([string]$Path)
  $values = @{}
  if (-not (Test-Path -LiteralPath $Path)) {
    return $values
  }
  foreach ($line in Get-Content -LiteralPath $Path) {
    if ($line -match "^\s*#" -or $line -match "^\s*$") {
      continue
    }
    if ($line -match "^\s*([^=]+?)\s*=\s*(.*)\s*$") {
      $key = $Matches[1].Trim()
      $value = $Matches[2].Trim().Trim('"').Trim("'")
      $values[$key] = $value
    }
  }
  return $values
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
    $content = "$Key=$Value`r`n" + $content
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

function Repair-LlamaCppConfig {
  param([string]$Path)
  $values = Read-DotEnv -Path $Path
  $changed = $false
  $defaults = [ordered]@{
    LLAMA_CPP_RUNTIME_PROFILE = "auto"
    LLAMA_CPP_PROFILE_SOURCE = "auto"
    LLAMA_CPP_IMAGE = "ghcr.io/ggml-org/llama.cpp:server@sha256:fcca4dac388066ca93db561751e8caf5fc7d46d9df5f00a7422026db68468e31"
    LLAMA_CPP_HF_REPO = "bartowski/Llama-3.2-3B-Instruct-GGUF:Q4_K_M"
    LLAMA_CPP_MODEL = "Llama-3.2-3B-Instruct-Q4_K_M"
    LLAMA_CPP_ACCELERATOR = "cpu"
    LLAMA_CPP_GPU_LAYERS = "0"
    LLAMA_CPP_FLASH_ATTN = "off"
    LLAMA_CPP_AUTO_BUILD_CUDA = "true"
    LLAMA_CPP_CONTEXT_SIZE = "8192"
    LLAMA_CPP_PARALLEL = "2"
    LLAMA_CPP_TEMPERATURE = "0.2"
    LLAMA_CPP_MAX_TOKENS = "512"
    LLAMA_CPP_TIMEOUT_SECONDS = "300"
    NVIDIA_VISIBLE_DEVICES = "all"
  }
  foreach ($entry in $defaults.GetEnumerator()) {
    if (-not $values[$entry.Key]) {
      Write-DotEnvValue -Path $Path -Key $entry.Key -Value $entry.Value
      $changed = $true
    }
  }
  foreach ($legacyKey in @("OLLAMA_IMAGE", "OLLAMA_MODEL", "OLLAMA_FALLBACK_MODEL", "OLLAMA_TEMPERATURE", "OLLAMA_NUM_PREDICT")) {
    if ($values.ContainsKey($legacyKey)) {
      Remove-DotEnvValue -Path $Path -Key $legacyKey
      $changed = $true
    }
  }
  return $changed
}

function Read-PlainToken {
  $secureToken = Read-Host "Token GitHub avec read:packages" -AsSecureString
  $tokenPtr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureToken)
  try {
    return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($tokenPtr)
  } finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($tokenPtr)
  }
}

function Get-GhcrBearerToken {
  param(
    [string]$Owner,
    [string]$ImageName,
    [string]$GithubUser,
    [string]$GithubToken
  )
  $basicBytes = [Text.Encoding]::ASCII.GetBytes("${GithubUser}:${GithubToken}")
  $basic = [Convert]::ToBase64String($basicBytes)
  $headers = @{ Authorization = "Basic $basic" }
  $scope = "repository:${Owner}/${ImageName}:pull"
  $uri = "https://ghcr.io/token?service=ghcr.io&scope=$([uri]::EscapeDataString($scope))"
  $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get
  return $response.token
}

function Get-GhcrTags {
  param(
    [string]$Owner,
    [string]$ImageName,
    [string]$BearerToken
  )
  $headers = @{ Authorization = "Bearer $BearerToken" }
  $uri = "https://ghcr.io/v2/${Owner}/${ImageName}/tags/list?n=100"
  $tags = @()
  $visited = @{}

  while ($uri) {
    if ($visited.ContainsKey($uri)) {
      throw "Boucle de pagination GHCR detectee pour ${ImageName}."
    }
    $visited[$uri] = $true

    $response = Invoke-WebRequest -UseBasicParsing -Uri $uri -Headers $headers -Method Get
    $payload = $response.Content | ConvertFrom-Json
    $tags += @($payload.tags)

    $currentUri = [uri]$uri
    $uri = $null
    $linkHeader = [string]$response.Headers["Link"]
    if ($linkHeader -match '<([^>]+)>\s*;\s*rel="?next"?') {
      $uri = ([uri]::new($currentUri, $Matches[1])).AbsoluteUri
    }
  }

  return @($tags | Select-Object -Unique)
}

function Get-LatestStableTag {
  param([string[]]$Tags)
  $stableTags = @($Tags | Where-Object { $_ -match "^v\d+\.\d+\.\d+$" })
  if ($stableTags.Count -eq 0) {
    return $null
  }
  return ($stableTags | Sort-Object -Descending -Property @{ Expression = { [version]($_.TrimStart("v")) } } | Select-Object -First 1)
}

$composePath = Join-Path $InstallDir "docker-compose.release.yml"
$envPath = Join-Path $InstallDir ".env"

$kitFiles = @(
  "docker-compose.release.yml",
  "docker-compose.accel.nvidia.yml",
  "docker-compose.accel.jetson.yml",
  "Dockerfile.llama-cuda",
  "client-common.sh",
  "client-platform.ps1",
  "install-client.sh",
  "update-client.sh",
  "check-update.sh",
  "backup-client.sh",
  "backup-maintenance.sh",
  "restore-client.sh",
  "uninstall-client.sh",
  "install-client.ps1",
  "update-client.ps1",
  "check-update.ps1",
  "backup-client.ps1",
  "backup-maintenance.ps1",
  "restore-client.ps1",
  "uninstall-client.ps1",
  "repair-terminal.sh",
  "verify-llama-gpu.sh",
  "repair-terminal.ps1",
  "AI-Deep-Monitor.cmd",
  "ai-deep-monitor.sh",
  "ai-deep-monitor.ps1",
  "README_CLIENT.md"
)
foreach ($fileName in $kitFiles) {
  $source = Resolve-KitSource $fileName
  if (-not $source) { continue }
  $target = Join-Path $InstallDir $fileName
  $sourcePath = (Resolve-Path -LiteralPath $source).Path
  $targetPath = $target
  if (Test-Path -LiteralPath $target) { $targetPath = (Resolve-Path -LiteralPath $target).Path }
  if ($sourcePath -ne $targetPath) {
    Copy-Item -LiteralPath $source -Destination $target -Force
  }
}
Remove-Item -LiteralPath (Join-Path $InstallDir "VERSION") -Force -ErrorAction SilentlyContinue
Sync-AiMonitorHostTerminalAgent -SourceRoot $kitRoot -InstallDir $InstallDir | Out-Null

if (-not (Test-Path -LiteralPath $composePath)) {
  throw "Compose introuvable: $composePath. Lance d'abord install-client.ps1."
}
if (-not (Test-Path -LiteralPath $envPath)) {
  throw ".env introuvable: $envPath. Lance d'abord install-client.ps1."
}

$envValues = Read-DotEnv -Path $envPath
Remove-DotEnvValue -Path $envPath -Key "KIT_VERSION"
$terminalValues = Read-DotEnv -Path $envPath
if (-not $terminalValues["HOST_TERMINAL_QUEUE_GID"]) {
  Write-DotEnvValue -Path $envPath -Key "HOST_TERMINAL_QUEUE_GID" -Value "10003"
}
if (-not $terminalValues["TERMINAL_SESSION_TTL_SECONDS"]) {
  Write-DotEnvValue -Path $envPath -Key "TERMINAL_SESSION_TTL_SECONDS" -Value "300"
}
if (-not $terminalValues["TERMINAL_POLICY_ADMIN_PASSWORD"]) {
  Write-DotEnvValue -Path $envPath -Key "TERMINAL_POLICY_ADMIN_PASSWORD" -Value "ysitech1234"
}
$authRepair = Repair-AuthConfig -Path $envPath
if ($authRepair.Changed) {
  Write-Host "Configuration d'authentification reparee; les volumes SQL et les comptes existants restent inchanges."
}
$llamaCppConfigChanged = Repair-LlamaCppConfig -Path $envPath
if ($llamaCppConfigChanged) {
  Write-Host "Configuration migree vers le runtime llama.cpp adaptatif; les donnees applicatives sont conservees."
}
$dockerPlatform = if ($NoStart) {
  Get-AiMonitorHostPlatform
} else {
  Require-Command "docker"
  docker version | Out-Null
  docker compose version | Out-Null
  Get-AiMonitorDockerPlatform
}
Write-DotEnvValue -Path $envPath -Key "DOCKER_PLATFORM" -Value $dockerPlatform

# Une application peut deja utiliser la derniere image alors que sa tache
# terminal execute encore un ancien agent. La maintenance standard doit donc
# synchroniser et redemarrer l'agent avant le retour "deja a jour".
if (-not $NoStart -and -not $SkipAgentInstall) {
  Install-AiMonitorHostTerminalAgent -InstallDir $InstallDir -Required
}

$currentVersion = $envValues["APP_VERSION"]
$githubOwner = $envValues["GITHUB_OWNER"]
if (-not $githubOwner) {
  $githubOwner = "jimmindev"
}
if (-not $currentVersion) {
  $currentVersion = "inconnue"
}

$githubUser = $envValues["UPDATE_CHECK_USER"]
$plainToken = $envValues["UPDATE_CHECK_TOKEN"]

if (-not $AppVersion) {
  Write-Host "Verification automatique de la derniere version stable..."
  Write-Host "Version installee: $currentVersion"

  if (-not $githubUser -or -not $plainToken) {
    $githubUser = Read-Host "Utilisateur GitHub"
    $plainToken = Read-PlainToken
  } else {
    Write-Host "Verification avec les identifiants GHCR configures dans .env."
  }

  $frontendBearer = Get-GhcrBearerToken -Owner $githubOwner -ImageName "ai-deep-monitor-frontend" -GithubUser $githubUser -GithubToken $plainToken
  $apiBearer = Get-GhcrBearerToken -Owner $githubOwner -ImageName "ai-deep-monitor-api" -GithubUser $githubUser -GithubToken $plainToken

  $frontendTags = Get-GhcrTags -Owner $githubOwner -ImageName "ai-deep-monitor-frontend" -BearerToken $frontendBearer
  $apiTags = Get-GhcrTags -Owner $githubOwner -ImageName "ai-deep-monitor-api" -BearerToken $apiBearer

  $latestFrontend = Get-LatestStableTag -Tags $frontendTags
  $latestApi = Get-LatestStableTag -Tags $apiTags

  if (-not $latestFrontend -or -not $latestApi) {
    throw "Impossible de trouver une version stable vX.Y.Z dans GHCR."
  }
  if ($latestFrontend -ne $latestApi) {
    throw "Incoherence GHCR: frontend=$latestFrontend api=$latestApi"
  }

  $AppVersion = $latestFrontend
  Write-Host "Derniere version stable disponible: $AppVersion"

}

$refreshImages = $currentVersion -eq $AppVersion
if ($refreshImages) {
  $currentLlamaProfile = (Read-DotEnv -Path $envPath)["LLAMA_CPP_RUNTIME_PROFILE"]
  if (-not $authRepair.Changed -and -not $llamaCppConfigChanged -and -not $RedetectLlamaRuntime -and -not $LlamaProfile -and $currentLlamaProfile -ne "auto") {
    Write-Host "Application deja en $AppVersion; les outils de maintenance sont synchronises."
    exit 0
  }
  Write-Host "L'application reste en $AppVersion; le deploiement est resynchronise pour $dockerPlatform."
} elseif (-not $Yes -and -not $versionWasSpecified) {
  $answer = Read-Host "Mettre a jour de $currentVersion vers $AppVersion ? (o/N)"
  if ($answer -notin @("o", "O", "oui", "OUI", "y", "Y", "yes", "YES")) {
    Write-Host "Mise a jour annulee."
    exit 0
  }
}

if (-not $SkipBackup -and -not $NoStart -and -not $refreshImages) {
  $backupScript = Join-Path $InstallDir "backup-client.ps1"
  if (-not (Test-Path -LiteralPath $backupScript)) {
    throw "backup-client.ps1 introuvable. Utilise -SkipBackup uniquement si une sauvegarde externe existe deja."
  }
  Write-Host "Sauvegarde automatique avant mise a jour..."
  & $backupScript -InstallDir $InstallDir
}

$backupPath = Join-Path $InstallDir (".env.backup-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
Copy-Item -LiteralPath $envPath -Destination $backupPath -Force
Protect-AiMonitorSensitiveFile -Path $backupPath
Write-DotEnvValue -Path $envPath -Key "APP_VERSION" -Value $AppVersion

Write-Host "Version cible: $AppVersion"
Write-Host "Backup .env: $backupPath"

if ($NoStart) {
  if ($LlamaProfile) {
    $profileSource = if ($LlamaProfile -eq "auto") { "auto" } else { "manual" }
    Write-DotEnvValue -Path $envPath -Key "LLAMA_CPP_RUNTIME_PROFILE" -Value $LlamaProfile
    Write-DotEnvValue -Path $envPath -Key "LLAMA_CPP_PROFILE_SOURCE" -Value $profileSource
  }
  Write-Host "NoStart actif: version mise a jour sans lancement Docker."
  if ($authRepair.BootstrapPassword) {
    Write-Host "Compte initial (seulement si aucun administrateur n'existe): admin / $($authRepair.BootstrapPassword)"
  }
  exit 0
}

if (-not $SkipDockerLogin) {
  if (-not $plainToken) {
    Write-Host "Connexion au registry prive GHCR."
    $githubUser = Read-Host "Utilisateur GitHub"
    $plainToken = Read-PlainToken
  }
  $plainToken | docker login ghcr.io -u $githubUser --password-stdin
  if ($LASTEXITCODE -ne 0) { throw "La connexion au registre prive GHCR a echoue." }
  Write-DotEnvValue -Path $envPath -Key "UPDATE_CHECK_ENABLED" -Value "true"
  Write-DotEnvValue -Path $envPath -Key "UPDATE_CHECK_USER" -Value $githubUser
  Write-DotEnvValue -Path $envPath -Key "UPDATE_CHECK_TOKEN" -Value $plainToken
  Protect-AiMonitorSensitiveFile -Path $envPath
}

Resolve-AiMonitorLlamaRuntime `
  -EnvPath $envPath `
  -InstallDir $InstallDir `
  -RequestedProfile $LlamaProfile `
  -RequireGpu:$RequireGpu `
  -Redetect:$RedetectLlamaRuntime
Invoke-AiMonitorCompose -ComposePath $composePath -EnvPath $envPath -CommandArguments @("config", "--quiet")
Invoke-AiMonitorComposePull -ComposePath $composePath -EnvPath $envPath
try {
  Invoke-AiMonitorCompose -ComposePath $composePath -EnvPath $envPath -CommandArguments @("up", "-d")
} catch {
  Write-Warning "Etat des services:"
  $composeArguments = Get-AiMonitorComposeArguments -ComposePath $composePath -EnvPath $envPath
  & docker compose @composeArguments ps
  Write-Warning "Derniers journaux utiles:"
  & docker compose @composeArguments logs --tail=120 mysql sandbox llama-cpp api collector
  throw
}
Invoke-AiMonitorCompose -ComposePath $composePath -EnvPath $envPath -CommandArguments @("ps")

Write-Host ""
Write-Host "Mise a jour terminee vers $AppVersion sur $dockerPlatform."
if ($authRepair.BootstrapPassword) {
  Write-Host "Compte initial, utilise uniquement si aucun administrateur n'existe deja:"
  Write-Host "Utilisateur: admin"
  Write-Host "Mot de passe: $($authRepair.BootstrapPassword)"
  Write-Host "Un compte existant conserve son mot de passe actuel."
}
