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
