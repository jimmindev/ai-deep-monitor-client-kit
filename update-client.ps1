param(
  [string]$InstallDir = "C:\ai-deep-monitor",
  [string]$AppVersion = "",
  [switch]$SkipDockerLogin,
  [switch]$NoStart,
  [switch]$Yes
)

$ErrorActionPreference = "Stop"

function Require-Command {
  param([string]$Name)
  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    throw "Commande introuvable: $Name"
  }
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

if (-not (Test-Path -LiteralPath $composePath)) {
  throw "Compose introuvable: $composePath. Lance d'abord install-client.ps1."
}
if (-not (Test-Path -LiteralPath $envPath)) {
  throw ".env introuvable: $envPath. Lance d'abord install-client.ps1."
}

$envValues = Read-DotEnv -Path $envPath
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

  if ($currentVersion -eq $AppVersion) {
    Write-Host "Application deja a jour."
    exit 0
  }

  if (-not $Yes) {
    $answer = Read-Host "Mettre a jour de $currentVersion vers $AppVersion ? (o/N)"
    if ($answer -notin @("o", "O", "oui", "OUI", "y", "Y", "yes", "YES")) {
      Write-Host "Mise a jour annulee."
      exit 0
    }
  }
}

$backupPath = Join-Path $InstallDir (".env.backup-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
Copy-Item -LiteralPath $envPath -Destination $backupPath -Force
Write-DotEnvValue -Path $envPath -Key "APP_VERSION" -Value $AppVersion

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
Write-Host "Mise a jour terminee vers $AppVersion."
