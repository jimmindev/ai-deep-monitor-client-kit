param(
  [string]$InstallDir = "C:\ai-deep-monitor",
  [string]$BackupDir = "",
  [ValidateSet("List", "Prune", "DeleteAll")]
  [string]$Action = "List",
  [ValidateRange(0, 10000)]
  [int]$Keep = 5,
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
