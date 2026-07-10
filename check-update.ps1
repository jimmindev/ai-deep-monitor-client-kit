param(
  [string]$InstallDir = "C:\ai-deep-monitor"
)

$ErrorActionPreference = "Stop"

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
      $values[$Matches[1].Trim()] = $Matches[2].Trim().Trim('"').Trim("'")
    }
  }
  return $values
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

$envPath = Join-Path $InstallDir ".env"
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

Write-Host "Version installee: $currentVersion"

$githubUser = Read-Host "Utilisateur GitHub"
$plainToken = Read-PlainToken

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

Write-Host "Derniere version stable disponible: $latestFrontend"

if ($currentVersion -eq $latestFrontend) {
  Write-Host "Etat: a jour"
} else {
  Write-Host "Etat: mise a jour disponible"
  Write-Host "Commande:"
  Write-Host ".\update-client.ps1"
}
