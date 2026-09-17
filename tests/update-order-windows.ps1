$ErrorActionPreference = "Stop"
$kit = Split-Path -Parent $PSScriptRoot
$temporaryRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$workspace = Join-Path $temporaryRoot ("ai-monitor-update-order-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $workspace | Out-Null
try {
  foreach ($result in @(0, 1)) {
    $install = Join-Path $workspace "client-$result"
    & (Join-Path $kit "scripts/windows/install-client.ps1") -InstallDir $install -NoStart -SkipDockerLogin *> $null
    $global:UpdateOrderCalls = [Collections.Generic.List[string]]::new()
    $global:UpdateOrderMigrationExit = $result
    function global:docker {
      param([Parameter(ValueFromRemainingArguments = $true)][string[]]$DockerArguments)
      $command = $DockerArguments -join " "
      $global:UpdateOrderCalls.Add($command)
      $global:LASTEXITCODE = 0
      if ($command -like "info --format *") { return "linux|amd64" }
      if ($command -like "*run --rm --no-deps api alembic upgrade head*") {
        $global:LASTEXITCODE = $global:UpdateOrderMigrationExit
      }
    }
    $failed = $false
    try {
      & (Join-Path $kit "scripts/windows/update-client.ps1") -InstallDir $install -AppVersion v0.1.99 -Yes -SkipBackup -SkipAgentInstall -SkipDockerLogin -SkipKitRefresh -LlamaProfile cpu *> $null
    } catch {
      $failed = $true
      if ($_.Exception.Message -notmatch "La migration a echoue") { throw }
    } finally {
      Remove-Item -LiteralPath Function:\global:docker
    }
    $calls = @($global:UpdateOrderCalls)
    $migration = -1
    $start = -1
    for ($i = 0; $i -lt $calls.Count; $i++) {
      if ($calls[$i] -like "*run --rm --no-deps api alembic upgrade head*") { $migration = $i }
      if ($calls[$i] -match " up -d$") { $start = $i }
    }
    if ($migration -lt 0) { throw "Migration not executed" }
    $envText = Get-Content -LiteralPath (Join-Path $install ".env") -Raw
    if ($result -eq 0) {
      if ($failed -or $start -le $migration -or $envText -notmatch "APP_VERSION=v0.1.99") { throw "Invalid successful update order" }
    } else {
      if (-not $failed -or $start -ne -1 -or $envText -match "APP_VERSION=v0.1.99") { throw "Failed migration restarted services or changed version" }
    }
    Write-Output "WINDOWS_UPDATE_ORDER_OK migration_exit=$result"
  }
} finally {
  $resolvedWorkspace = [IO.Path]::GetFullPath($workspace)
  if (-not $resolvedWorkspace.StartsWith($temporaryRoot, [StringComparison]::OrdinalIgnoreCase)) { throw "Unsafe cleanup path" }
  Remove-Item -LiteralPath $resolvedWorkspace -Recurse -Force
  Remove-Variable UpdateOrderCalls, UpdateOrderMigrationExit -Scope Global -ErrorAction SilentlyContinue
}

# The intentionally failed Docker call must not become the CI process result.
$global:LASTEXITCODE = 0
