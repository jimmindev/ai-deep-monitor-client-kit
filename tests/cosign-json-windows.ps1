$ErrorActionPreference = "Stop"
$kit = Split-Path -Parent $PSScriptRoot
$temporaryRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$workspace = Join-Path $temporaryRoot ("ai-monitor-cosign-json-test-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $workspace | Out-Null
Copy-Item -LiteralPath (Join-Path $kit "scripts/windows/verify-images.ps1") -Destination $workspace
Copy-Item -LiteralPath (Join-Path $kit "deploy/signing-policy.json") -Destination $workspace
$verifier = Join-Path $workspace "verify-images.ps1"
try {
  foreach ($mode in @("valid", "missing", "invalid-signature")) {
    $global:CosignJsonMode = $mode
    $global:CosignJsonCalls = [Collections.Generic.List[string]]::new()
    function global:docker {
      $command = $args -join " "
      $global:LASTEXITCODE = 0
      if ($command -like "image inspect *") {
        if ($global:CosignJsonMode -eq "missing") { return '["ghcr.io/other/image@sha256:aaaa"]' }
        $repository = [string]$args[2]
        $repository = $repository.Substring(0, $repository.LastIndexOf(":"))
        return ('["' + $repository + '@sha256:' + ('a' * 64) + '"]')
      }
      if ($command -like "run --rm *") {
        $global:CosignJsonCalls.Add($command)
        if ($global:CosignJsonMode -eq "invalid-signature") { $global:LASTEXITCODE = 1 }
      }
    }
    $failed = $false
    try {
      & $verifier -AppVersion v0.1.158 -GithubUser fixture -GithubToken fixture *> $null
    } catch { $failed = $true; $failureMessage = $_.Exception.Message }
    if ($mode -eq "valid") {
      if ($failed -or $global:CosignJsonCalls.Count -ne 2) { throw "Valid single-item RepoDigests arrays were not verified: $failureMessage" }
      foreach ($command in $global:CosignJsonCalls) {
        if ($command -notmatch "@sha256:[a-f0-9]{64}$" -or $command -notmatch "--certificate-identity ") { throw "Verification did not use a pinned digest and signer" }
      }
    } elseif (-not $failed) { throw "Invalid digest or signature was accepted" }
    Write-Output "COSIGN_JSON_OK $mode"
  }
} finally {
  Remove-Item -LiteralPath Function:\global:docker -ErrorAction SilentlyContinue
  Remove-Variable CosignJsonMode, CosignJsonCalls -Scope Global -ErrorAction SilentlyContinue
  $resolvedWorkspace = [IO.Path]::GetFullPath($workspace)
  if (-not $resolvedWorkspace.StartsWith($temporaryRoot, [StringComparison]::OrdinalIgnoreCase)) { throw "Unsafe cleanup path" }
  Remove-Item -LiteralPath (Join-Path $resolvedWorkspace "verify-images.ps1") -Force
  Remove-Item -LiteralPath (Join-Path $resolvedWorkspace "signing-policy.json") -Force
  Remove-Item -LiteralPath $resolvedWorkspace
}
$global:LASTEXITCODE = 0
