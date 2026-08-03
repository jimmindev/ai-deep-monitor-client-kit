function Resolve-AiMonitorDockerPlatform {
  param(
    [Parameter(Mandatory = $true)][string]$OsType,
    [Parameter(Mandatory = $true)][string]$Architecture
  )

  if ($OsType.Trim().ToLowerInvariant() -ne "linux") {
    throw "Docker utilise les conteneurs $OsType. AI Deep Monitor exige les conteneurs Linux. Dans Docker Desktop, ouvre le menu Docker puis choisis 'Switch to Linux containers' et relance."
  }

  switch ($Architecture.Trim().ToLowerInvariant()) {
    { $_ -in @("amd64", "x86_64", "x64") } { return "linux/amd64" }
    { $_ -in @("arm64", "arm64/v8", "aarch64") } { return "linux/arm64" }
    default {
      throw "Architecture Docker non prise en charge: $Architecture. Architectures supportees: amd64 et arm64."
    }
  }
}

function Get-AiMonitorDockerPlatform {
  $rawPlatform = (& docker info --format "{{.OSType}}|{{.Architecture}}" 2>$null).Trim()
  if ($LASTEXITCODE -ne 0 -or -not $rawPlatform -or $rawPlatform -notmatch "\|") {
    throw "Impossible d'identifier la plateforme du moteur Docker."
  }

  $parts = $rawPlatform.Split("|", 2)
  $platform = Resolve-AiMonitorDockerPlatform -OsType $parts[0] -Architecture $parts[1]
  Write-Host "Plateforme Docker detectee: $platform."
  return $platform
}

function Get-AiMonitorHostPlatform {
  $architecture = [Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
  switch ($architecture.ToLowerInvariant()) {
    "x64" { return "linux/amd64" }
    "arm64" { return "linux/arm64" }
    default {
      throw "Architecture hote non prise en charge: $architecture. Architectures supportees: amd64 et arm64."
    }
  }
}

function Sync-AiMonitorHostTerminalAgent {
  param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [Parameter(Mandatory = $true)][string]$InstallDir
  )

  $sourceDir = Join-Path $SourceRoot "host_terminal_agent"
  if (-not (Test-Path -LiteralPath $sourceDir -PathType Container)) {
    return $false
  }

  $targetDir = Join-Path $InstallDir "host_terminal_agent"
  New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
  $sourcePath = (Resolve-Path -LiteralPath $sourceDir).Path
  $targetPath = (Resolve-Path -LiteralPath $targetDir).Path
  if ($sourcePath -eq $targetPath) {
    return $true
  }

  foreach ($name in @(
    "agent.py",
    "terminal_policy.py",
    "install_linux_service.sh",
    "uninstall_linux_service.sh",
    "install_windows_task.ps1",
    "uninstall_windows_task.ps1",
    "README.md"
  )) {
    $source = Join-Path $sourceDir $name
    if (Test-Path -LiteralPath $source -PathType Leaf) {
      Copy-Item -LiteralPath $source -Destination (Join-Path $targetDir $name) -Force
    }
  }
  return $true
}

function Install-AiMonitorHostTerminalAgent {
  param([Parameter(Mandatory = $true)][string]$InstallDir)

  $installer = Join-Path $InstallDir "host_terminal_agent\install_windows_task.ps1"
  if (-not (Test-Path -LiteralPath $installer -PathType Leaf)) {
    Write-Warning "Agent terminal hote absent du kit."
    return
  }
  if (-not (Get-Command python.exe -ErrorAction SilentlyContinue)) {
    if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
      Write-Warning "Python 3 est requis par le terminal hote et winget est indisponible."
      return
    }
    Write-Host "Python 3 est requis par le terminal hote; installation automatique..."
    & winget.exe install `
      --id Python.Python.3.12 `
      --exact `
      --scope machine `
      --silent `
      --accept-package-agreements `
      --accept-source-agreements
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machinePath;$userPath"
  }
  if (-not (Get-Command python.exe -ErrorAction SilentlyContinue)) {
    Write-Warning "Python 3 n'est pas disponible; installez-le puis relancez la mise a jour du kit."
    return
  }
  try {
    & $installer
  } catch {
    Write-Warning "L'application reste utilisable, mais l'agent terminal hote doit etre installe manuellement: $($_.Exception.Message)"
  }
}
