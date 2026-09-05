$ErrorActionPreference = "Stop"
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$testDir = Join-Path $repositoryRoot ".tmp-windows-smoke"
$frontendListener = $null
$apiListener = $null
$agentProcess = $null
$clientKitReleaseDir = Join-Path ([IO.Path]::GetTempPath()) ("ai-monitor-kit-release-test-" + [guid]::NewGuid().ToString("N"))

try {
  try {
    & (Join-Path $repositoryRoot "scripts\windows\install-client.ps1") `
      -InstallDir (Join-Path $testDir "unsafe-login-bypass") `
      -SkipDockerLogin
    throw "Le contournement GHCR a ete accepte pour une installation reelle."
  } catch {
    if ($_.Exception.Message -notmatch "SkipDockerLogin est reserve") { throw }
  }

  $updateScriptSource = Get-Content -LiteralPath (Join-Path $repositoryRoot "scripts\windows\update-client.ps1") -Raw
  $agentRepairIndex = $updateScriptSource.IndexOf('Install-AiMonitorHostTerminalAgent -InstallDir $InstallDir -Required')
  $sameVersionIndex = $updateScriptSource.IndexOf('$refreshImages = $currentVersion -eq $AppVersion')
  if ($agentRepairIndex -lt 0 -or $sameVersionIndex -lt 0 -or $agentRepairIndex -gt $sameVersionIndex) {
    throw "L'agent terminal doit etre repare avant le retour application deja a jour."
  }
  $launcherSource = Get-Content -LiteralPath (Join-Path $repositoryRoot "ai-deep-monitor.ps1") -Raw
  if (-not $launcherSource.Contains("Mettre a jour l'application, le Client Kit et le terminal")) {
    throw "Le menu Windows ne precise pas que la mise a jour entretient le Client Kit et le terminal."
  }

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
    "docker-compose.accel.nvidia.yml",
    "docker-compose.accel.jetson.yml",
    "Dockerfile.llama-cuda",
    "ai-deep-monitor.sh",
    "install-client.ps1",
    "install-client.sh",
    "client-platform.ps1",
    "client-common.sh",
    "backup-maintenance.ps1",
    "backup-maintenance.sh",
    "repair-terminal.ps1",
    "repair-terminal.sh",
    "verify-llama-gpu.sh",
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
  if ($envContent -notmatch "(?m)^APP_VERSION=v0\.1\.22\r?$") {
    throw "La version applicative attendue est absente."
  }
  if ($envContent -match "(?m)^KIT_VERSION=") {
    throw "Le Client Kit ne doit plus ecrire de version dans .env."
  }
  if ($envContent -notmatch "(?m)^LLAMA_CPP_MODEL=Llama-3\.2-3B-Instruct-Q4_K_M\r?$" -or
      $envContent -notmatch "(?m)^LLAMA_CPP_RUNTIME_PROFILE=auto\r?$" -or
      $envContent -notmatch "(?m)^LLAMA_CPP_ACCELERATOR=cpu\r?$" -or
      $envContent -notmatch "(?m)^LLAMA_CPP_GPU_LAYERS=0\r?$" -or
      $envContent -notmatch "(?m)^LLAMA_CPP_FLASH_ATTN=off\r?$" -or
      $envContent -notmatch "(?m)^NVIDIA_VISIBLE_DEVICES=all\r?$") {
    throw "La configuration llama.cpp adaptative attendue est absente."
  }
  if ($envContent -notmatch "(?m)^HOST_TERMINAL_QUEUE_GID=10003\r?$" -or
      $envContent -notmatch "(?m)^TERMINAL_SESSION_TTL_SECONDS=300\r?$") {
    throw "La configuration du terminal hote est incomplete."
  }
  if ($envContent -notmatch "(?m)^TERMINAL_POLICY_ADMIN_PASSWORD=ysitech1234\r?$") {
    throw "Le mot de passe de gestion des regles terminal est absent."
  }
  & python (Join-Path $testDir "host_terminal_agent\agent.py") --help | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "L'agent terminal autonome ne demarre pas." }

  # Simule la release permanente et verifie le remplacement effectif des
  # installateurs, de la documentation et de l'agent sans lancer Docker.
  $fixtureParent = Join-Path $clientKitReleaseDir "package"
  $fixtureRoot = Join-Path $fixtureParent "ai-deep-monitor-client-kit"
  $releaseArchive = Join-Path $clientKitReleaseDir "ai-deep-monitor-client-kit.zip"
  New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null
  foreach ($directory in @("deploy", "docs", "host_terminal_agent", "scripts")) {
    Copy-Item -LiteralPath (Join-Path $repositoryRoot $directory) -Destination $fixtureRoot -Recurse -Force
  }
  foreach ($file in @("AI-Deep-Monitor.cmd", "ai-deep-monitor.ps1", "ai-deep-monitor.sh", "CHANGELOG.md", "README.md")) {
    Copy-Item -LiteralPath (Join-Path $repositoryRoot $file) -Destination $fixtureRoot -Force
  }
  Add-Content -LiteralPath (Join-Path $fixtureRoot "docs\installation.md") -Value "`nCLIENT_KIT_SELF_REFRESH_OK"
  Compress-Archive -LiteralPath $fixtureRoot -DestinationPath $releaseArchive -Force
  $releaseHash = (Get-FileHash -LiteralPath $releaseArchive -Algorithm SHA256).Hash.ToLowerInvariant()
  Set-Content `
    -LiteralPath (Join-Path $clientKitReleaseDir "ai-deep-monitor-client-kit-SHA256.txt") `
    -Value "$releaseHash  ai-deep-monitor-client-kit.zip" `
    -Encoding ASCII
  Set-Content -LiteralPath (Join-Path $testDir "README_CLIENT.md") -Value "ANCIEN_CLIENT_KIT" -Encoding ASCII
  $previousReleaseBase = $env:AI_DEEP_MONITOR_CLIENT_KIT_RELEASE_BASE
  try {
    $env:AI_DEEP_MONITOR_CLIENT_KIT_RELEASE_BASE = $clientKitReleaseDir
    & (Join-Path $testDir "update-client.ps1") `
      -InstallDir $testDir `
      -RefreshKitOnly `
      -SkipAgentInstall
  } finally {
    $env:AI_DEEP_MONITOR_CLIENT_KIT_RELEASE_BASE = $previousReleaseBase
  }
  $refreshedReadme = Get-Content -LiteralPath (Join-Path $testDir "README_CLIENT.md") -Raw
  $refreshedUpdater = Get-Content -LiteralPath (Join-Path $testDir "update-client.ps1") -Raw
  if ($refreshedReadme -notmatch "CLIENT_KIT_SELF_REFRESH_OK" -or
      $refreshedUpdater -notmatch "Get-LatestClientKitStage") {
    throw "La mise a jour Windows n'a pas remplace les fichiers du Client Kit."
  }

  Set-Content `
    -LiteralPath (Join-Path $clientKitReleaseDir "ai-deep-monitor-client-kit-SHA256.txt") `
    -Value "$(('0' * 64))  ai-deep-monitor-client-kit.zip" `
    -Encoding ASCII
  Set-Content -LiteralPath (Join-Path $testDir "README_CLIENT.md") -Value "FICHIER_A_CONSERVER" -Encoding ASCII
  $invalidArchiveRejected = $false
  try {
    $env:AI_DEEP_MONITOR_CLIENT_KIT_RELEASE_BASE = $clientKitReleaseDir
    & (Join-Path $testDir "update-client.ps1") `
      -InstallDir $testDir `
      -RefreshKitOnly `
      -SkipAgentInstall
  } catch {
    if ($_.Exception.Message -match "corrompue") {
      $invalidArchiveRejected = $true
    } else {
      throw
    }
  } finally {
    $env:AI_DEEP_MONITOR_CLIENT_KIT_RELEASE_BASE = $previousReleaseBase
  }
  if (-not $invalidArchiveRejected) {
    throw "Une archive Client Kit avec une somme invalide a ete acceptee."
  }
  if ((Get-Content -LiteralPath (Join-Path $testDir "README_CLIENT.md") -Raw).Trim() -ne "FICHIER_A_CONSERVER") {
    throw "Une archive Client Kit invalide a modifie l'installation Windows."
  }

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

  $envContent = (($envContent -split "`r?`n") | Where-Object {
    $_ -notmatch '^(LLAMA_CPP_|NVIDIA_VISIBLE_DEVICES=)'
  }) -join "`r`n"
  $envContent += "`r`nOLLAMA_MODEL=llama3.1`r`nOLLAMA_FALLBACK_MODEL=llama3.1"
  $envContent = $envContent `
    -replace "(?m)^HOST_TERMINAL_QUEUE_GID=.*$", "HOST_TERMINAL_QUEUE_GID=12003" `
    -replace "(?m)^TERMINAL_SESSION_TTL_SECONDS=.*$", "TERMINAL_SESSION_TTL_SECONDS=420"
  $envContent += "`r`nKIT_VERSION=v0.1.15`r`n"
  Set-Content -LiteralPath $envPath -Value $envContent -Encoding UTF8
  & (Join-Path $testDir "update-client.ps1") `
    -InstallDir $testDir `
    -SkipKitRefresh `
    -NoStart `
    -AppVersion "v0.1.9"
  $envContent = Get-Content -LiteralPath $envPath -Raw
  if ($envContent -match "(?m)^KIT_VERSION=") {
    throw "L'ancienne version du Client Kit n'a pas ete retiree pendant la migration."
  }
  if ($envContent -match "(?m)^OLLAMA_" -or
      $envContent -notmatch "(?m)^LLAMA_CPP_MODEL=Llama-3\.2-3B-Instruct-Q4_K_M\r?$" -or
      $envContent -notmatch "(?m)^LLAMA_CPP_RUNTIME_PROFILE=auto\r?$" -or
      $envContent -notmatch "(?m)^LLAMA_CPP_ACCELERATOR=cpu\r?$" -or
      $envContent -notmatch "(?m)^LLAMA_CPP_GPU_LAYERS=0\r?$" -or
      $envContent -notmatch "(?m)^NVIDIA_VISIBLE_DEVICES=all\r?$") {
    throw "La migration d'Ollama vers llama.cpp adaptatif a echoue."
  }
  if ($envContent -notmatch "(?m)^HOST_TERMINAL_QUEUE_GID=12003\r?$" -or
      $envContent -notmatch "(?m)^TERMINAL_SESSION_TTL_SECONDS=420\r?$") {
    throw "La mise a jour a ecrase une configuration terminal personnalisee."
  }

  & $launcherPath -InstallDir $testDir -Command help | Out-Null

  $installedBackupScript = Get-Content -LiteralPath (Join-Path $testDir "backup-client.ps1") -Raw
  if ($installedBackupScript -match '/app/generated_backups' -or
      $installedBackupScript -notmatch 'generatedBackupsIncluded\s*=\s*\$false' -or
      $installedBackupScript -notmatch 'CompressionLevel Fastest') {
    throw "La sauvegarde Windows imbrique encore les anciennes archives."
  }
  foreach ($runtimeAwareScript in @("backup-client.ps1", "restore-client.ps1", "uninstall-client.ps1")) {
    $runtimeAwareSource = Get-Content -LiteralPath (Join-Path $testDir $runtimeAwareScript) -Raw
    if ($runtimeAwareSource -notmatch 'Get-AiMonitorComposeArguments') {
      throw "$runtimeAwareScript ignore le profil llama.cpp memorise."
    }
  }
  if ((Get-Content -LiteralPath $launcherPath -Raw) -notmatch 'docker-compose\.accel\.nvidia\.yml') {
    throw "Le lanceur Windows ignore l'override NVIDIA lors des commandes start/stop/status."
  }
  $installedAgent = Get-Content -LiteralPath (Join-Path $testDir "host_terminal_agent\agent.py") -Raw
  if ($installedAgent -notmatch 'MAX_UPDATE_SECONDS = 3_600') {
    throw "Le delai de maintenance Jetson n'a pas ete augmente."
  }
  if ($installedAgent -notmatch 'def refresh_client_kit' -or
      $installedAgent -notmatch 'client_kit_update_failed') {
    throw "L'agent terminal n'actualise pas le Client Kit avant l'application."
  }

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
  $llamaService = $composeJson.services."llama-cpp"
  $llamaCommand = @($llamaService.command)
  $gpuLayerIndex = [Array]::IndexOf($llamaCommand, "--n-gpu-layers")
  $flashAttnIndex = [Array]::IndexOf($llamaCommand, "--flash-attn")
  if (-not $llamaService -or
      $llamaService.image -notmatch '^ghcr\.io/ggml-org/llama\.cpp:server@sha256:' -or
      $gpuLayerIndex -lt 0 -or $llamaCommand[$gpuLayerIndex + 1] -ne "0" -or
      $flashAttnIndex -lt 0 -or $llamaCommand[$flashAttnIndex + 1] -ne "off" -or
      $llamaService.gpus) {
    throw "Le service llama.cpp CPU de base n'est pas configure correctement."
  }
  $nvidiaComposeJson = & docker compose `
    -f (Join-Path $repositoryRoot "deploy\docker-compose.release.yml") `
    -f (Join-Path $repositoryRoot "deploy\docker-compose.accel.nvidia.yml") `
    --env-file $envPath `
    config --format json | ConvertFrom-Json
  if (-not $nvidiaComposeJson.services."llama-cpp".gpus) {
    throw "L'override NVIDIA n'expose pas le GPU a llama.cpp."
  }
  if (-not $composeJson.services.api.depends_on."llama-cpp") {
    throw "L'API ne depend pas du service llama.cpp."
  }
  $mysqlHealthCommand = [string]$composeJson.services.mysql.healthcheck.test[1]
  if ($mysqlHealthCommand -notmatch '--protocol=tcp' -or
      $mysqlHealthCommand -notmatch '127\.0\.0\.1') {
    throw "Le healthcheck MySQL peut encore valider le serveur temporaire via son socket."
  }
  $apiCommand = (@($composeJson.services.api.command) -join ' ')
  if ($apiCommand -notmatch 'until alembic upgrade head' -or
      $apiCommand -notmatch 'DB_INIT_RETRIES') {
    throw "Le demarrage de l'API ne retente pas les migrations transitoires."
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
  if (Test-Path -LiteralPath $clientKitReleaseDir) {
    Remove-Item -LiteralPath $clientKitReleaseDir -Recurse -Force
  }
}
