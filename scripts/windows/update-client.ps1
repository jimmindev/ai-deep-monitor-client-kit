param(
  [string]$InstallDir = "C:\ai-deep-monitor",
  [string]$AppVersion = "",
  [switch]$SkipDockerLogin,
  [switch]$SkipBackup,
  [switch]$NoStart,
  [switch]$Yes
)

$ErrorActionPreference = "Stop"
$kitRoot = $PSScriptRoot
$repositoryRoot = Join-Path $PSScriptRoot "..\.."
if (Test-Path -LiteralPath (Join-Path $repositoryRoot "VERSION")) {
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
  $uri = "https://ghcr.io/v2/${Owner}/${ImageName}/tags/list"
  $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get
  return @($response.tags)
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
  "ai-deep-monitor.sh",
  "ai-deep-monitor.ps1",
  "README_CLIENT.md",
  "VERSION"
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

if (-not (Test-Path -LiteralPath $composePath)) {
  throw "Compose introuvable: $composePath. Lance d'abord install-client.ps1."
}
if (-not (Test-Path -LiteralPath $envPath)) {
  throw ".env introuvable: $envPath. Lance d'abord install-client.ps1."
}

$envValues = Read-DotEnv -Path $envPath
$previousKitVersion = $envValues["KIT_VERSION"]
Write-DotEnvValue -Path $envPath -Key "KIT_VERSION" -Value "v0.1.7"
$authRepair = Repair-AuthConfig -Path $envPath
if ($authRepair.Changed) {
  Write-Host "Configuration d'authentification reparee; les volumes SQL et les comptes existants restent inchanges."
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
  if ($previousKitVersion -eq "v0.1.7" -and -not $authRepair.Changed) {
    Write-Host "Application deja en $AppVersion et kit deja en v0.1.7."
    exit 0
  }
  Write-Host "L'application reste en $AppVersion; le deploiement est resynchronise pour $dockerPlatform avec le kit v0.1.7."
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
Write-DotEnvValue -Path $envPath -Key "APP_VERSION" -Value $AppVersion

Write-Host "Version cible: $AppVersion"
Write-Host "Backup .env: $backupPath"

if ($NoStart) {
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
  Write-DotEnvValue -Path $envPath -Key "UPDATE_CHECK_ENABLED" -Value "true"
  Write-DotEnvValue -Path $envPath -Key "UPDATE_CHECK_USER" -Value $githubUser
  Write-DotEnvValue -Path $envPath -Key "UPDATE_CHECK_TOKEN" -Value $plainToken
}

docker compose -f $composePath --env-file $envPath pull
docker compose -f $composePath --env-file $envPath up -d
docker compose -f $composePath --env-file $envPath ps

Write-Host ""
Write-Host "Mise a jour terminee vers $AppVersion sur $dockerPlatform."
if ($authRepair.BootstrapPassword) {
  Write-Host "Compte initial, utilise uniquement si aucun administrateur n'existe deja:"
  Write-Host "Utilisateur: admin"
  Write-Host "Mot de passe: $($authRepair.BootstrapPassword)"
  Write-Host "Un compte existant conserve son mot de passe actuel."
}
