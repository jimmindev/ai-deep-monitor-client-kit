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
  if ($envContent -notmatch "(?m)^KIT_VERSION=v0\.1\.10\r?$") {
    throw "La version du Client Kit attendue est absente."
  }
  if ($envContent -notmatch "(?m)^OLLAMA_MODEL=llama3\.2:3b\r?$") {
    throw "Le modele Ollama principal attendu est absent."
  }
  if ($envContent -notmatch "(?m)^OLLAMA_FALLBACK_MODEL=llama3\.2:3b\r?$") {
    throw "Le modele Ollama de secours attendu est absent."
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
  & (Join-Path $testDir "backup-maintenance.ps1") `
    -InstallDir $testDir `
    -BackupDir $backupDir `
    -Action DeleteSelected `
    -File "ai-deep-monitor-middle.zip" `
    -Yes
  if (@(Get-ChildItem -LiteralPath $backupDir -File).Count -ne 1) {
    throw "La suppression ciblee Windows n'a pas conserve exactement une sauvegarde."
  }
  if (Test-Path -LiteralPath $middleBackup.FullName) {
    throw "La sauvegarde Windows selectionnee n'a pas ete supprimee."
  }
  if (-not (Test-Path -LiteralPath $newBackup.FullName)) {
    throw "La suppression ciblee Windows a supprime une sauvegarde non selectionnee."
  }
  Write-Output "WINDOWS_SMOKE_OK"
} finally {
  if ($frontendListener) { $frontendListener.Stop() }
  if ($apiListener) { $apiListener.Stop() }
  if (Test-Path -LiteralPath $testDir) {
    Remove-Item -LiteralPath $testDir -Recurse -Force
  }
}
