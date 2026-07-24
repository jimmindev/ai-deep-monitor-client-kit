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

  & (Join-Path $repositoryRoot "install-client.ps1") `
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
  Write-Output "WINDOWS_SMOKE_OK"
} finally {
  if ($frontendListener) { $frontendListener.Stop() }
  if ($apiListener) { $apiListener.Stop() }
  if (Test-Path -LiteralPath $testDir) {
    Remove-Item -LiteralPath $testDir -Recurse -Force
  }
}
