$ErrorActionPreference = "Stop"
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$testDir = Join-Path $repositoryRoot ".tmp-windows-smoke"
$frontendListener = $null
$apiListener = $null
$agentProcess = $null

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
    "repair-terminal.ps1",
    "repair-terminal.sh",
    "AI-Deep-Monitor.cmd",
    "README_CLIENT.md"
  )) {
    if (-not (Test-Path -LiteralPath (Join-Path $testDir $requiredFile))) {
      throw "Fichier client non copie: $requiredFile"
    }
  }
  foreach ($agentFile in @("agent.py", "terminal_policy.py", "install_windows_task.ps1")) {
    if (-not (Test-Path -LiteralPath (Join-Path $testDir "host_terminal_agent\$agentFile"))) {
      throw "Fichier de l'agent terminal non copie: $agentFile"
    }
  }
  $envContent = Get-Content -LiteralPath $envPath -Raw
  if ($envContent -match "(?m)^FRONTEND_PORT=18080\r?$") {
    throw "Le port web occupe n'a pas ete remplace."
  }
  if ($envContent -match "(?m)^API_PORT=18081\r?$") {
    throw "Le port API occupe n'a pas ete remplace."
  }
  if ($envContent -notmatch "(?m)^APP_VERSION=v0\.1\.8\r?$") {
    throw "La version applicative attendue est absente."
  }
  if ($envContent -notmatch "(?m)^KIT_VERSION=v0\.1\.15\r?$") {
    throw "La version du Client Kit attendue est absente."
  }
  if ($envContent -notmatch "(?m)^OLLAMA_MODEL=llama3\.2:3b\r?$") {
    throw "Le modele Ollama principal attendu est absent."
  }
  if ($envContent -notmatch "(?m)^OLLAMA_FALLBACK_MODEL=llama3\.2:1b\r?$") {
    throw "Le modele Ollama de secours attendu est absent."
  }
  if ($envContent -notmatch "(?m)^HOST_TERMINAL_QUEUE_GID=10003\r?$" -or
      $envContent -notmatch "(?m)^TERMINAL_SESSION_TTL_SECONDS=300\r?$") {
    throw "La configuration du terminal hote est incomplete."
  }
  & python (Join-Path $testDir "host_terminal_agent\agent.py") --help | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "L'agent terminal autonome ne demarre pas." }

  $agentPath = Join-Path $testDir "host_terminal_agent\agent.py"
  $agentState = Join-Path $testDir "host-terminal-test-state"
  $pythonPath = (Get-Command python.exe -ErrorAction Stop).Source
  $agentProcess = Start-Process `
    -FilePath $pythonPath `
    -ArgumentList @(
      $agentPath,
      "--jobs-dir", (Join-Path $testDir "host_terminal_jobs"),
      "--install-dir", $testDir,
      "--state-dir", $agentState
    ) `
    -WindowStyle Hidden `
    -PassThru
  . (Join-Path $testDir "client-platform.ps1")
  if (-not (Test-AiMonitorHostTerminalAgent -InstallDir $testDir -TimeoutSeconds 15)) {
    throw "Le controle de sante du terminal Windows n'a pas detecte l'agent."
  }

  $envContent = $envContent `
    -replace "(?m)^OLLAMA_MODEL=.*$", "OLLAMA_MODEL=llama3.1" `
    -replace "(?m)^OLLAMA_FALLBACK_MODEL=.*$", "OLLAMA_FALLBACK_MODEL=llama3.1" `
    -replace "(?m)^HOST_TERMINAL_QUEUE_GID=.*$", "HOST_TERMINAL_QUEUE_GID=12003" `
    -replace "(?m)^TERMINAL_SESSION_TTL_SECONDS=.*$", "TERMINAL_SESSION_TTL_SECONDS=420"
  Set-Content -LiteralPath $envPath -Value $envContent -Encoding UTF8
  & (Join-Path $testDir "update-client.ps1") `
    -InstallDir $testDir `
    -NoStart `
    -AppVersion "v0.1.8"
  $envContent = Get-Content -LiteralPath $envPath -Raw
  if ($envContent -notmatch "(?m)^OLLAMA_MODEL=llama3\.2:3b\r?$" -or
      $envContent -notmatch "(?m)^OLLAMA_FALLBACK_MODEL=llama3\.2:1b\r?$") {
    throw "La migration de l'ancienne configuration Ollama a echoue."
  }
  if ($envContent -notmatch "(?m)^HOST_TERMINAL_QUEUE_GID=12003\r?$" -or
      $envContent -notmatch "(?m)^TERMINAL_SESSION_TTL_SECONDS=420\r?$") {
    throw "La mise a jour a ecrase une configuration terminal personnalisee."
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

  $composeJson = & docker compose `
    -f (Join-Path $repositoryRoot "deploy\docker-compose.release.yml") `
    --env-file $envPath `
    config --format json | ConvertFrom-Json
  $modelCommand = [string]$composeJson.services."ollama-models".command[0]
  if ($modelCommand -notmatch 'for model in "\$\$\{OLLAMA_MODEL\}" "\$\$\{OLLAMA_FALLBACK_MODEL\}"' -or
      $modelCommand -notmatch 'ollama pull "\$\$\{model\}"') {
    throw "La commande d'initialisation Ollama a ete decoupee par Docker Compose."
  }
  if (-not $composeJson.services.collector) {
    throw "Le service collector est absent du Compose client."
  }
  Write-Output "WINDOWS_SMOKE_OK"
} finally {
  if ($agentProcess -and -not $agentProcess.HasExited) {
    Stop-Process -Id $agentProcess.Id -Force -ErrorAction SilentlyContinue
    $agentProcess.WaitForExit(5000) | Out-Null
  }
  if ($frontendListener) { $frontendListener.Stop() }
  if ($apiListener) { $apiListener.Stop() }
  if (Test-Path -LiteralPath $testDir) {
    Remove-Item -LiteralPath $testDir -Recurse -Force
  }
}
