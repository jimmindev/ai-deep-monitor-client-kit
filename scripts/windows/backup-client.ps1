param(
  [string]$InstallDir = "C:\ai-deep-monitor",
  [string]$DestinationDir = ""
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
  foreach ($line in Get-Content -LiteralPath $Path) {
    if ($line -match "^\s*#" -or $line -match "^\s*$") { continue }
    if ($line -match "^\s*([^=]+?)\s*=\s*(.*)\s*$") {
      $values[$Matches[1].Trim()] = $Matches[2].Trim().Trim('"').Trim("'")
    }
  }
  return $values
}

function Wait-ForHealthyContainer {
  param(
    [string]$ContainerId,
    [int]$TimeoutSeconds = 120
  )
  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  while ((Get-Date) -lt $deadline) {
    $state = (& docker inspect --format "{{.State.Status}}|{{if .State.Health}}{{.State.Health.Status}}{{end}}" $ContainerId 2>$null).Trim()
    if ($state -match "^running\|(healthy)?$") { return }
    if ($state -eq "running|") { return }
    Start-Sleep -Seconds 2
  }
  throw "Le conteneur $ContainerId n'est pas pret apres $TimeoutSeconds secondes."
}

$composePath = Join-Path $InstallDir "docker-compose.release.yml"
$envPath = Join-Path $InstallDir ".env"
if (-not (Test-Path -LiteralPath $composePath)) { throw "Compose introuvable: $composePath" }
if (-not (Test-Path -LiteralPath $envPath)) { throw ".env introuvable: $envPath" }

Require-Command "docker"
docker version | Out-Null
docker compose version | Out-Null

if (-not $DestinationDir) {
  $parentDir = Split-Path -Parent $InstallDir
  if (-not $parentDir) { $parentDir = "C:\" }
  $DestinationDir = Join-Path $parentDir "ai-deep-monitor-backups"
}
$destination = New-Item -ItemType Directory -Force -Path $DestinationDir
$envValues = Read-DotEnv -Path $envPath
$version = $envValues["APP_VERSION"]
if (-not $version) { $version = "unknown" }

$composeArgs = @("compose", "-f", $composePath, "--env-file", $envPath)
& docker @composeArgs config --quiet
& docker @composeArgs up -d mysql | Out-Null
$mysqlRows = @(& docker @composeArgs ps -q mysql)
$mysqlContainer = if ($mysqlRows.Count -gt 0) { ([string]$mysqlRows[0]).Trim() } else { "" }
if (-not $mysqlContainer) { throw "Conteneur MySQL introuvable." }
Wait-ForHealthyContainer -ContainerId $mysqlContainer

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$stagingDir = Join-Path ([IO.Path]::GetTempPath()) "ai-monitor-backup-$timestamp-$PID"
$archivePath = Join-Path $destination.FullName "ai-deep-monitor-$version-$timestamp.zip"
New-Item -ItemType Directory -Force -Path $stagingDir | Out-Null

try {
  Write-Host "Sauvegarde MySQL..."
  $containerDump = "/tmp/ai-monitor-$timestamp.sql"
  $dumpCommand = 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysqldump -uroot --single-transaction --routines --triggers --events --hex-blob --default-character-set=utf8mb4 "$MYSQL_DATABASE" > "' + $containerDump + '"'
  & docker exec $mysqlContainer sh -c $dumpCommand
  if ($LASTEXITCODE -ne 0) { throw "Echec du dump MySQL." }
  & docker cp "${mysqlContainer}:$containerDump" (Join-Path $stagingDir "mysql.sql")
  & docker exec $mysqlContainer rm -f $containerDump | Out-Null

  $apiRows = @(& docker @composeArgs ps -a -q api)
  $apiContainer = if ($apiRows.Count -gt 0) { ([string]$apiRows[0]).Trim() } else { "" }
  $includedPaths = @()
  if ($apiContainer) {
    foreach ($entry in @(
      @{ Source = "/app/data/."; Target = "api-data" },
      @{ Source = "/app/uploaded_mibs/."; Target = "uploaded-mibs" },
      @{ Source = "/app/generated_backups/."; Target = "generated-backups" }
    )) {
      $target = Join-Path $stagingDir $entry.Target
      New-Item -ItemType Directory -Force -Path $target | Out-Null
      & docker cp "${apiContainer}:$($entry.Source)" $target 2>$null
      if ($LASTEXITCODE -eq 0) { $includedPaths += $entry.Target }
    }
  } else {
    Write-Warning "Conteneur API absent: seul MySQL sera sauvegarde."
  }

  $dumpHash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $stagingDir "mysql.sql")).Hash
  $manifest = [ordered]@{
    formatVersion = 1
    application = "AI Deep Monitor"
    appVersion = $version
    createdAt = (Get-Date).ToUniversalTime().ToString("o")
    computerName = $env:COMPUTERNAME
    mysqlSha256 = $dumpHash
    includedPaths = $includedPaths
    ollamaIncluded = $false
  }
  $manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $stagingDir "manifest.json") -Encoding UTF8

  Compress-Archive -Path (Join-Path $stagingDir "*") -DestinationPath $archivePath -CompressionLevel Optimal
  Write-Host ""
  Write-Host "Sauvegarde terminee: $archivePath"
  Write-Host "Le modele Ollama n'est pas inclus et sera retelcharge si necessaire."
} finally {
  if (Test-Path -LiteralPath $stagingDir) {
    Remove-Item -LiteralPath $stagingDir -Recurse -Force
  }
}
