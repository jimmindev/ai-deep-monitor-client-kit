param(
  [string]$BaseDir = (Split-Path -Parent $PSScriptRoot),
  [switch]$Yes
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $BaseDir -PathType Container)) {
  throw "Dossier de recherche introuvable: $BaseDir"
}

$resolvedBase = (Resolve-Path -LiteralPath $BaseDir).Path
$resolvedScriptDir = (Resolve-Path -LiteralPath $PSScriptRoot).Path
$normalizedBase = [System.IO.Path]::GetFullPath($resolvedBase).TrimEnd(
  [System.IO.Path]::DirectorySeparatorChar,
  [System.IO.Path]::AltDirectorySeparatorChar
)
$normalizedScriptDir = [System.IO.Path]::GetFullPath($resolvedScriptDir).TrimEnd(
  [System.IO.Path]::DirectorySeparatorChar,
  [System.IO.Path]::AltDirectorySeparatorChar
)
$candidates = @(
  Get-ChildItem -LiteralPath $normalizedBase -Force |
    Where-Object {
      $_.Name -ne "ai-deep-monitor-client-kit" -and (
        $_.Name -like "ai-deep-monitor-client-kit-v*" -or
        $_.Name -like "ai-deep-monitor-client-kit-release-v*" -or
        $_.Name -eq "ai-deep-monitor-client-kit.tar.gz" -or
        $_.Name -eq "ai-deep-monitor-client-kit.zip"
      )
    }
)

foreach ($candidate in $candidates) {
  $candidateParent = [System.IO.Path]::GetFullPath(
    (Split-Path -Parent $candidate.FullName)
  ).TrimEnd(
    [System.IO.Path]::DirectorySeparatorChar,
    [System.IO.Path]::AltDirectorySeparatorChar
  )
  if (-not [string]::Equals(
    $candidateParent,
    $normalizedBase,
    [System.StringComparison]::OrdinalIgnoreCase
  )) {
    throw "Cible refusee hors du dossier de recherche: $($candidate.FullName)"
  }
  $candidatePath = [System.IO.Path]::GetFullPath($candidate.FullName).TrimEnd(
    [System.IO.Path]::DirectorySeparatorChar,
    [System.IO.Path]::AltDirectorySeparatorChar
  )
  if (
    $candidate.PSIsContainer -and
    [string]::Equals(
      $candidatePath,
      $normalizedScriptDir,
      [System.StringComparison]::OrdinalIgnoreCase
    )
  ) {
    throw "Suppression du dossier courant refusee: $($candidate.FullName)"
  }
}

if ($candidates.Count -eq 0) {
  Write-Host "[AI Deep Monitor] Aucun ancien Client Kit a nettoyer dans $resolvedBase."
  exit 0
}

Write-Host "[AI Deep Monitor] Elements obsoletes detectes dans ${normalizedBase}:"
foreach ($candidate in $candidates) {
  Write-Host "  - $($candidate.Name)"
}

Write-Host ""
Write-Host "[AI Deep Monitor] Sont conserves:"
Write-Host "  - $(Join-Path $normalizedBase 'ai-deep-monitor-client-kit')"
Write-Host "  - C:\ai-deep-monitor"
Write-Host "  - les volumes Docker, MySQL et les sauvegardes"

if (-not $Yes) {
  $answer = Read-Host "Supprimer uniquement les elements listes ? (o/N)"
  if ($answer -notin @("o", "O", "oui", "OUI")) {
    Write-Host "[AI Deep Monitor] Nettoyage annule."
    exit 0
  }
}

foreach ($candidate in $candidates) {
  Remove-Item -LiteralPath $candidate.FullName -Recurse -Force
  Write-Host "[AI Deep Monitor] Supprime: $($candidate.Name)"
}

Write-Host "[AI Deep Monitor] Nettoyage termine. L'installation AI Deep Monitor est conservee."
