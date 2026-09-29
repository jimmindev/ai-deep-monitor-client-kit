param(
  [string]$GithubOwner = "jimmindev",
  [Parameter(Mandatory = $true)][string]$AppVersion,
  [string]$GithubUser = "",
  [string]$GithubToken = ""
)

$ErrorActionPreference = "Stop"

$trustedOwner = "jimmindev"
$trustedRepository = "ai-deep-monitor"
$issuer = "https://token.actions.githubusercontent.com"
$cosignImage = "ghcr.io/sigstore/cosign/cosign:v3.1.3@sha256:9e5c2f2edc34351160407ca3416c61855bdf9403c3c5936e0f0be7fc261611b8"
$policyPath = Join-Path $PSScriptRoot "signing-policy.json"

function Invoke-DockerChecked {
  param([Parameter(Mandatory = $true)][string[]]$Arguments)
  & docker @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "La commande Docker a echoue (code $LASTEXITCODE): docker $($Arguments -join ' ')"
  }
}

function Get-LocalDigestReference {
  param([Parameter(Mandatory = $true)][string]$Repository)
  $taggedReference = "${Repository}:${AppVersion}"
  $json = & docker image inspect $taggedReference --format '{{json .RepoDigests}}'
  if ($LASTEXITCODE -ne 0) {
    throw "Image locale introuvable apres telechargement: $taggedReference"
  }
  $repoDigests = @($json | ConvertFrom-Json)
  $digestReference = $repoDigests |
    Where-Object { $_ -is [string] -and $_.StartsWith("${Repository}@sha256:", [StringComparison]::OrdinalIgnoreCase) } |
    Select-Object -First 1
  if (-not $digestReference) {
    throw "Digest immuable introuvable pour $taggedReference. La mise a jour est bloquee."
  }
  return $digestReference
}

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
  throw "Docker est requis pour verifier les signatures des images."
}
if ($GithubOwner -ne $trustedOwner) {
  throw "Proprietaire GHCR non approuve: $GithubOwner. Seul $trustedOwner est autorise."
}
if ($AppVersion -notmatch '^v\d+\.\d+\.\d+$') {
  throw "Version invalide pour la verification de signature: $AppVersion"
}
$GithubUser = if ($GithubUser) { $GithubUser } elseif ($env:GHCR_USER) { $env:GHCR_USER } else { $env:UPDATE_CHECK_USER }
$GithubToken = if ($GithubToken) { $GithubToken } elseif ($env:GHCR_TOKEN) { $env:GHCR_TOKEN } else { $env:UPDATE_CHECK_TOKEN }
if (-not $GithubUser -or -not $GithubToken) {
  throw "Les identifiants GHCR sont requis pour verifier les signatures privees."
}
if (-not (Test-Path -LiteralPath $policyPath)) {
  throw "Politique de signature absente. La mise a jour est bloquee."
}
$policy = Get-Content -LiteralPath $policyPath -Raw | ConvertFrom-Json
if ([string]$policy.local_from_version -notmatch '^v\d+\.\d+\.\d+$') {
  throw "Version de transition Cosign invalide."
}
$targetVersionValue = [version]($AppVersion.Substring(1))
$transitionVersionValue = [version](([string]$policy.local_from_version).Substring(1))
$useLocalSigner = $targetVersionValue -ge $transitionVersionValue
if ($useLocalSigner -and (-not $policy.identity -or $policy.identity -eq "PENDING_COSIGN_PILOT" -or -not $policy.issuer)) {
  throw "Identite Cosign locale non approuvee. La mise a jour est bloquee."
}

$escapedVersion = [regex]::Escape($AppVersion)
$identityRegexp = "^https://github\.com/$trustedOwner/$trustedRepository/\.github/workflows/docker-images\.yml@(refs/heads/main|refs/tags/$escapedVersion)$"
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$dockerConfigDir = Join-Path $tempRoot ("ai-deep-monitor-cosign-" + [guid]::NewGuid().ToString("N"))

New-Item -ItemType Directory -Path $dockerConfigDir -Force | Out-Null
try {
  $GithubToken | & docker --config $dockerConfigDir login ghcr.io --username $GithubUser --password-stdin
  if ($LASTEXITCODE -ne 0) {
    throw "Authentification temporaire GHCR impossible pour la verification Cosign."
  }

  $repositories = @(
    "ghcr.io/$trustedOwner/ai-deep-monitor-api",
    "ghcr.io/$trustedOwner/ai-deep-monitor-frontend"
  )
  foreach ($repository in $repositories) {
    $digestReference = Get-LocalDigestReference -Repository $repository
    Write-Host "Verification de la signature: $digestReference"
    $verifyArguments = @(
      "run", "--rm",
      "--env", "DOCKER_CONFIG=/auth",
      "--volume", "${dockerConfigDir}:/auth:ro",
      $cosignImage,
      "verify"
    )
    if ($useLocalSigner) {
      $verifyArguments += @("--certificate-identity", [string]$policy.identity, "--certificate-oidc-issuer", [string]$policy.issuer)
    } else {
      $verifyArguments += @("--certificate-identity-regexp", $identityRegexp, "--certificate-oidc-issuer", $issuer)
    }
    $verifyArguments += $digestReference
    Invoke-DockerChecked -Arguments $verifyArguments
  }
  Write-Host "Signatures Cosign valides pour les images $AppVersion."
} finally {
  $resolvedConfigDir = [IO.Path]::GetFullPath($dockerConfigDir)
  if ($resolvedConfigDir.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase)) {
    Remove-Item -LiteralPath $resolvedConfigDir -Recurse -Force -ErrorAction SilentlyContinue
  }
}
