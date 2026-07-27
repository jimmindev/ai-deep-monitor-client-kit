param(
  [string]$InstallDir = "C:\ai-deep-monitor",
  [string]$BackupDir = "",
  [ValidateSet("List", "Prune", "DeleteSelected", "DeleteAll")]
  [string]$Action = "List",
  [ValidateRange(0, 10000)]
  [int]$Keep = 5,
  [string[]]$File = @(),
  [switch]$Yes
)

$ErrorActionPreference = "Stop"

if (-not $BackupDir) {
  $parentDir = Split-Path -Parent $InstallDir
  if (-not $parentDir) { $parentDir = "C:\" }
  $BackupDir = Join-Path $parentDir "ai-deep-monitor-backups"
}

$backups = @()
if (Test-Path -LiteralPath $BackupDir -PathType Container) {
  $backups = @(Get-ChildItem -LiteralPath $BackupDir -File |
    Where-Object {
      $_.Name -like "ai-deep-monitor-*.zip" -or
      $_.Name -like "ai-deep-monitor-*.tar.gz"
    } |
    Sort-Object LastWriteTime -Descending)
}

function Show-Backups {
  if ($backups.Count -eq 0) {
    Write-Host "Aucune sauvegarde dans $BackupDir."
    return
  }
  Write-Host ""
  Write-Host "Sauvegardes ($($backups.Count)) - $BackupDir"
  $backups |
    Select-Object @{Name="Date"; Expression={$_.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")}},
      @{Name="Taille"; Expression={"{0:N1} MB" -f ($_.Length / 1MB)}},
      Name |
    Format-Table -AutoSize
}

function Show-NumberedBackups {
  Write-Host ""
  Write-Host "Sauvegardes disponibles"
  for ($index = 0; $index -lt $backups.Count; $index++) {
    $backup = $backups[$index]
    Write-Host ("  {0,2}. {1,8:N1} MB  {2}" -f ($index + 1), ($backup.Length / 1MB), $backup.Name)
  }
}

function ConvertFrom-BackupSelection {
  param([string]$Selection)

  $selectedIndexes = [System.Collections.Generic.HashSet[int]]::new()
  foreach ($partValue in ($Selection -split ",")) {
    $part = $partValue.Trim()
    if ($part -match "^(\d+)-(\d+)$") {
      $start = [int]$Matches[1]
      $end = [int]$Matches[2]
      if ($start -gt $end) { throw "Plage invalide: $part" }
      foreach ($number in $start..$end) {
        if ($number -lt 1 -or $number -gt $backups.Count) {
          throw "Numero hors liste: $number"
        }
        [void]$selectedIndexes.Add($number - 1)
      }
    } elseif ($part -match "^\d+$") {
      $number = [int]$part
      if ($number -lt 1 -or $number -gt $backups.Count) {
        throw "Numero hors liste: $number"
      }
      [void]$selectedIndexes.Add($number - 1)
    } else {
      throw "Selection invalide: $part"
    }
  }

  return @(
    for ($index = 0; $index -lt $backups.Count; $index++) {
      if ($selectedIndexes.Contains($index)) { $backups[$index] }
    }
  )
}

function Select-Backups {
  if ($File.Count -gt 0) {
    return @(
      foreach ($requestedName in $File) {
        $match = @($backups | Where-Object Name -CEQ $requestedName)
        if ($match.Count -eq 0) { throw "Sauvegarde introuvable: $requestedName" }
        $match[0]
      }
    )
  }

  Show-NumberedBackups
  $selection = Read-Host "Numeros a supprimer (exemple: 1,3,5-7; vide pour annuler)"
  if (-not $selection) { return @() }
  return @(ConvertFrom-BackupSelection -Selection $selection)
}

switch ($Action) {
  "List" {
    Show-Backups
  }
  "Prune" {
    if ($backups.Count -le $Keep) {
      Write-Host "$($backups.Count) sauvegarde(s): rien a supprimer (conservation: $Keep)."
      return
    }
    Show-Backups
    $toDelete = @($backups | Select-Object -Skip $Keep)
    if (-not $Yes) {
      $answer = Read-Host "Supprimer les $($toDelete.Count) sauvegarde(s) les plus anciennes ? (o/N)"
      if ($answer -notmatch "^(o|oui|y|yes)$") {
        Write-Host "Nettoyage annule."
        return
      }
    }
    $toDelete | Remove-Item -Force
    Write-Host "Nettoyage termine. $Keep sauvegarde(s) recente(s) conservee(s)."
  }
  "DeleteSelected" {
    if ($backups.Count -eq 0) {
      Write-Host "Aucune sauvegarde a supprimer."
      return
    }
    $toDelete = @(Select-Backups)
    if ($toDelete.Count -eq 0) {
      Write-Host "Selection annulee."
      return
    }
    Write-Host ""
    Write-Host "Sauvegarde(s) selectionnee(s):"
    $toDelete | ForEach-Object { Write-Host "  - $($_.Name)" }
    if (-not $Yes) {
      $answer = Read-Host "Supprimer definitivement ces $($toDelete.Count) sauvegarde(s) ? (o/N)"
      if ($answer -notmatch "^(o|oui|y|yes)$") {
        Write-Host "Suppression annulee."
        return
      }
    }
    $toDelete | ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force }
    Write-Host "$($toDelete.Count) sauvegarde(s) supprimee(s)."
  }
  "DeleteAll" {
    if ($backups.Count -eq 0) {
      Write-Host "Aucune sauvegarde a supprimer."
      return
    }
    Show-Backups
    if (-not $Yes) {
      $answer = Read-Host "Saisis SUPPRIMER SAUVEGARDES pour confirmer"
      if ($answer -cne "SUPPRIMER SAUVEGARDES") {
        Write-Host "Suppression annulee."
        return
      }
    }
    $backups | Remove-Item -Force
    Write-Host "Toutes les sauvegardes AI Deep Monitor ont ete supprimees."
  }
}
