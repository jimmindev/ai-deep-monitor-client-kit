$ErrorActionPreference = "Stop"
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$testDir = Join-Path $repositoryRoot ".tmp-windows-smoke"
$frontendListener = $null
$apiListener = $null

try {
  if (Test-Path -LiteralPath $testDir) {
    Remove-Item -LiteralPath $testDir -Recurse -Force
  }

  $frontendListener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 18080)
  $apiListener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 18081)
  $frontendListener.Start()
  $apiListener.Start()

  & (Join-Path $repositoryRoot "scripts\windows\install-client.ps1") `
    -InstallDir $testDir `
    -NoStart `
    -SkipDockerLogin `
    -FrontendPort 18080 `
    -ApiPort 18081

  $envPath = Join-Path $testDir ".env"
  $launcherPath = Join-Path $testDir "ai-deep-monitor.ps1"
  if (-not (Test-Path -LiteralPath $launcherPath)) {
    throw "Le lanceur Windows unifie n'a pas ete copie."
  }
  foreach ($requiredFile in @(
    "docker-compose.release.yml",
    "ai-deep-monitor.sh",
    "install-client.ps1",
    "install-client.sh",
    "client-platform.ps1",
    "client-common.sh",
    "backup-maintenance.ps1",
    "backup-maintenance.sh",
    "README_CLIENT.md"
  )) {
    if (-not (Test-Path -LiteralPath (Join-Path $testDir $requiredFile))) {
      throw "Fichier client non copie: $requiredFile"
    }
  }
  $envContent = Get-Content -LiteralPath $envPath -Raw
  if ($envContent -match "(?m)^FRONTEND_PORT=18080\r?$") {
    throw "Le port web occupe n'a pas ete remplace."
  }
  if ($envContent -match "(?m)^API_PORT=18081\r?$") {
    throw "Le port API occupe n'a pas ete remplace."
  }
  if ($envContent -notmatch "(?m)^APP_VERSION=v0\.1\.5\r?$") {
    throw "La version applicative attendue est absente."
  }

  & $launcherPath -InstallDir $testDir -Command help | Out-Null

  $backupDir = Join-Path $testDir "test-backups"
  New-Item -ItemType Directory -Path $backupDir | Out-Null
  $oldBackup = New-Item -ItemType File -Path (Join-Path $backupDir "ai-deep-monitor-old.zip")
  $middleBackup = New-Item -ItemType File -Path (Join-Path $backupDir "ai-deep-monitor-middle.zip")
  $newBackup = New-Item -ItemType File -Path (Join-Path $backupDir "ai-deep-monitor-new.zip")
  $oldBackup.LastWriteTime = [datetime]"2026-01-01"
  $middleBackup.LastWriteTime = [datetime]"2026-01-02"
  $newBackup.LastWriteTime = [datetime]"2026-01-03"
  & (Join-Path $testDir "backup-maintenance.ps1") `
    -InstallDir $testDir `
    -BackupDir $backupDir `
    -Action Prune `
    -Keep 2 `
    -Yes
  if (@(Get-ChildItem -LiteralPath $backupDir -File).Count -ne 2) {
    throw "La retention Windows n'a pas conserve exactement deux sauvegardes."
  }
  if (Test-Path -LiteralPath $oldBackup.FullName) {
    throw "La plus ancienne sauvegarde Windows n'a pas ete supprimee."
  }
  Write-Output "WINDOWS_SMOKE_OK"
} finally {
  if ($frontendListener) { $frontendListener.Stop() }
  if ($apiListener) { $apiListener.Stop() }
  if (Test-Path -LiteralPath $testDir) {
    Remove-Item -LiteralPath $testDir -Recurse -Force
  }
}
