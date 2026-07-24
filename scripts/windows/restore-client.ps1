param(
  [Parameter(Mandatory = $true)]
  [string]$BackupFile,
  [string]$InstallDir = "C:\ai-deep-monitor",
  [switch]$NoStart,
  [switch]$Yes
)

$ErrorActionPreference = "Stop"

function Require-Command {
  param([string]$Name)
  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    throw "Commande introuvable: $Name"
  }
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

function Restore-ApiDirectory {
  param(
    [string]$ContainerId,
    [string]$SourcePath,
    [string]$TargetPath
  )
  if (-not (Test-Path -LiteralPath $SourcePath)) { return }
  $sourceSpec = Join-Path $SourcePath "."
  & docker cp $sourceSpec "${ContainerId}:$TargetPath"
  if ($LASTEXITCODE -ne 0) { throw "Impossible de restaurer $TargetPath." }
}

$backupPath = (Resolve-Path -LiteralPath $BackupFile).Path
$composePath = Join-Path $InstallDir "docker-compose.release.yml"
$envPath = Join-Path $InstallDir ".env"
if (-not (Test-Path -LiteralPath $composePath)) { throw "Compose introuvable: $composePath" }
if (-not (Test-Path -LiteralPath $envPath)) { throw ".env introuvable: $envPath" }

Require-Command "docker"
docker version | Out-Null
docker compose version | Out-Null

$stagingDir = Join-Path ([IO.Path]::GetTempPath()) "ai-monitor-restore-$(Get-Date -Format 'yyyyMMdd-HHmmss')-$PID"
New-Item -ItemType Directory -Force -Path $stagingDir | Out-Null

try {
  Expand-Archive -LiteralPath $backupPath -DestinationPath $stagingDir -Force
  $manifestPath = Join-Path $stagingDir "manifest.json"
  $dumpPath = Join-Path $stagingDir "mysql.sql"
  if (-not (Test-Path -LiteralPath $manifestPath)) { throw "Manifest de sauvegarde absent." }
  if (-not (Test-Path -LiteralPath $dumpPath)) { throw "Dump mysql.sql absent." }

  $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
  $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $dumpPath).Hash
  if ($manifest.mysqlSha256 -and $manifest.mysqlSha256 -ne $actualHash) {
    throw "Le dump MySQL ne correspond pas au checksum du manifest."
  }

  Write-Host "Sauvegarde: $backupPath"
  Write-Host "Version sauvegardee: $($manifest.appVersion)"
  Write-Host "Date UTC: $($manifest.createdAt)"
  Write-Warning "La restauration remplace la base et les donnees applicatives actuelles."
  if (-not $Yes) {
    $answer = Read-Host "Continuer ? (o/N)"
    if ($answer -notin @("o", "O", "oui", "OUI", "y", "Y", "yes", "YES")) {
      Write-Host "Restauration annulee."
      exit 0
    }
  }

  $composeArgs = @("compose", "-f", $composePath, "--env-file", $envPath)
  & docker @composeArgs config --quiet
  & docker @composeArgs up -d mysql | Out-Null
  $mysqlRows = @(& docker @composeArgs ps -q mysql)
  $mysqlContainer = if ($mysqlRows.Count -gt 0) { ([string]$mysqlRows[0]).Trim() } else { "" }
  if (-not $mysqlContainer) { throw "Conteneur MySQL introuvable." }
  Wait-ForHealthyContainer -ContainerId $mysqlContainer

  & docker @composeArgs stop frontend api | Out-Null
  $containerDump = "/tmp/ai-monitor-restore-$PID.sql"
  & docker cp $dumpPath "${mysqlContainer}:$containerDump"
  if ($LASTEXITCODE -ne 0) { throw "Copie du dump vers MySQL impossible." }
  $restoreCommand = 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql -uroot "$MYSQL_DATABASE" < "' + $containerDump + '"'
  & docker exec $mysqlContainer sh -c $restoreCommand
  if ($LASTEXITCODE -ne 0) { throw "Echec de la restauration MySQL." }
  & docker exec $mysqlContainer rm -f $containerDump | Out-Null

  $apiDirectories = @(
    [PSCustomObject]@{ Source = (Join-Path $stagingDir "api-data"); Target = "/app/data" }
    [PSCustomObject]@{ Source = (Join-Path $stagingDir "uploaded-mibs"); Target = "/app/uploaded_mibs" }
    [PSCustomObject]@{ Source = (Join-Path $stagingDir "generated-backups"); Target = "/app/generated_backups" }
  )
  $availableApiDirectories = @($apiDirectories | Where-Object { Test-Path -LiteralPath $_.Source })
  $apiRows = @(& docker @composeArgs ps -a -q api)
  $apiContainer = if ($apiRows.Count -gt 0) { ([string]$apiRows[0]).Trim() } else { "" }
  if ($availableApiDirectories.Count -gt 0 -and $apiContainer) {
    & docker start $apiContainer | Out-Null
    Start-Sleep -Seconds 2
    foreach ($entry in $availableApiDirectories) {
      & docker exec $apiContainer sh -c "mkdir -p '$($entry.Target)' && find '$($entry.Target)' -mindepth 1 -delete"
      if ($LASTEXITCODE -ne 0) { throw "Impossible de vider $($entry.Target)." }
    }
    & docker stop $apiContainer | Out-Null
    foreach ($entry in $availableApiDirectories) {
      Restore-ApiDirectory -ContainerId $apiContainer -SourcePath $entry.Source -TargetPath $entry.Target
    }
  } elseif ($availableApiDirectories.Count -gt 0) {
    Write-Warning "Donnees API presentes dans la sauvegarde, mais conteneur API introuvable. Reinstallez le kit puis relancez la restauration."
  }

  if ($NoStart) {
    Write-Host "NoStart actif: donnees restaurees, services applicatifs laisses arretes."
  } else {
    & docker @composeArgs up -d
    & docker @composeArgs ps
  }
  Write-Host ""
  Write-Host "Restauration terminee."
} finally {
  if (Test-Path -LiteralPath $stagingDir) {
    Remove-Item -LiteralPath $stagingDir -Recurse -Force
  }
}
