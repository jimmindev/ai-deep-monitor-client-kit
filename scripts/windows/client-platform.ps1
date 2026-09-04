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

function Get-AiMonitorComposeArguments {
  param(
    [Parameter(Mandatory = $true)][string]$ComposePath,
    [Parameter(Mandatory = $true)][string]$EnvPath
  )

  $profile = ""
  foreach ($line in Get-Content -LiteralPath $EnvPath) {
    if ($line -match '^LLAMA_CPP_RUNTIME_PROFILE=(.+)$') { $profile = $Matches[1].Trim(); break }
  }
  $arguments = @("-f", $ComposePath)
  switch ($profile) {
    "nvidia" {
      $override = Join-Path (Split-Path -Parent $ComposePath) "docker-compose.accel.nvidia.yml"
      if (-not (Test-Path -LiteralPath $override -PathType Leaf)) { throw "Override llama.cpp absent: $override" }
      $arguments += @("-f", $override)
    }
    "jetson" {
      $override = Join-Path (Split-Path -Parent $ComposePath) "docker-compose.accel.jetson.yml"
      if (-not (Test-Path -LiteralPath $override -PathType Leaf)) { throw "Override llama.cpp absent: $override" }
      $arguments += @("-f", $override)
    }
  }
  $arguments += @("--env-file", $EnvPath)
  return ,$arguments
}

function Invoke-AiMonitorCompose {
  param(
    [Parameter(Mandatory = $true)][string]$ComposePath,
    [Parameter(Mandatory = $true)][string]$EnvPath,
    [Parameter(Mandatory = $true)][string[]]$CommandArguments
  )
  $arguments = Get-AiMonitorComposeArguments -ComposePath $ComposePath -EnvPath $EnvPath
  & docker compose @arguments @CommandArguments
  if ($LASTEXITCODE -ne 0) { throw "docker compose $($CommandArguments -join ' ') a echoue." }
}

function Get-AiMonitorCudaVersion {
  if (-not (Get-Command nvidia-smi -ErrorAction SilentlyContinue)) { return $null }
  $text = (& nvidia-smi 2>$null | Out-String)
  if ($LASTEXITCODE -eq 0 -and $text -match "CUDA Version:\s*([0-9]+\.[0-9]+)") { return $Matches[1] }
  return $null
}

function Get-AiMonitorCudaArchitecture {
  if (-not (Get-Command nvidia-smi -ErrorAction SilentlyContinue)) { return $null }
  $compute = (& nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>$null | Select-Object -First 1)
  if ($LASTEXITCODE -eq 0 -and $compute) {
    $normalized = ([string]$compute).Trim().Replace(".", "")
    if ($normalized -match "^\d+$") { return $normalized }
  }
  return $null
}

function Get-AiMonitorCudaBaseImages {
  param([Parameter(Mandatory = $true)][string]$Version)
  $mapping = @{
    "13.0" = @("nvidia/cuda:13.0.1-devel-ubuntu24.04", "nvidia/cuda:13.0.1-runtime-ubuntu24.04")
    "12.9" = @("nvidia/cuda:12.9.1-devel-ubuntu24.04", "nvidia/cuda:12.9.1-runtime-ubuntu24.04")
    "12.8" = @("nvidia/cuda:12.8.1-devel-ubuntu24.04", "nvidia/cuda:12.8.1-runtime-ubuntu24.04")
    "12.6" = @("nvidia/cuda:12.6.3-devel-ubuntu24.04", "nvidia/cuda:12.6.3-runtime-ubuntu24.04")
    "12.4" = @("nvidia/cuda:12.4.1-devel-ubuntu22.04", "nvidia/cuda:12.4.1-runtime-ubuntu22.04")
    "12.2" = @("nvidia/cuda:12.2.2-devel-ubuntu22.04", "nvidia/cuda:12.2.2-runtime-ubuntu22.04")
    "12.1" = @("nvidia/cuda:12.1.1-devel-ubuntu22.04", "nvidia/cuda:12.1.1-runtime-ubuntu22.04")
    "11.8" = @("nvidia/cuda:11.8.0-devel-ubuntu22.04", "nvidia/cuda:11.8.0-runtime-ubuntu22.04")
    "11.4" = @("nvidia/cuda:11.4.3-devel-ubuntu20.04", "nvidia/cuda:11.4.3-runtime-ubuntu20.04")
  }
  return $mapping[$Version]
}

function Test-AiMonitorLlamaGpuImage {
  param([Parameter(Mandatory = $true)][string]$Image)
  Write-Host "Verification du GPU depuis le conteneur llama.cpp..."
  $output = & docker run --rm --gpus all $Image --list-devices 2>&1
  if ($LASTEXITCODE -ne 0) {
    $output | Write-Warning
    return $false
  }
  $output | Write-Host
  return [bool]($output -match "CUDA0:")
}

function Test-AiMonitorGpuRuntime {
  param([Parameter(Mandatory = $true)][string]$Image)
  & docker run --rm --gpus all --entrypoint /bin/true $Image 2>$null
  return $LASTEXITCODE -eq 0
}

function Build-AiMonitorLlamaCudaImage {
  param(
    [Parameter(Mandatory = $true)][string]$EnvPath,
    [Parameter(Mandatory = $true)][string]$InstallDir
  )
  $runtime = Read-DotEnv -Path $EnvPath
  $cudaVersion = Get-AiMonitorCudaVersion
  $cudaArchitecture = Get-AiMonitorCudaArchitecture
  if (-not $cudaVersion -or -not $cudaArchitecture) { return $null }
  $baseImages = if ($runtime["LLAMA_CPP_CUDA_DEVEL_IMAGE"] -and $runtime["LLAMA_CPP_CUDA_RUNTIME_IMAGE"]) {
    @($runtime["LLAMA_CPP_CUDA_DEVEL_IMAGE"], $runtime["LLAMA_CPP_CUDA_RUNTIME_IMAGE"])
  } else {
    Get-AiMonitorCudaBaseImages -Version $cudaVersion
  }
  if (-not $baseImages -or $baseImages.Count -ne 2) {
    Write-Warning "CUDA $cudaVersion n'a pas encore de base automatique. Definissez LLAMA_CPP_CUDA_DEVEL_IMAGE et LLAMA_CPP_CUDA_RUNTIME_IMAGE."
    return $null
  }
  $dockerfile = Join-Path $InstallDir "Dockerfile.llama-cuda"
  if (-not (Test-Path -LiteralPath $dockerfile -PathType Leaf)) { return $null }
  $localImage = "local/ai-deep-monitor-llama-cpp:cuda-$cudaVersion-sm$cudaArchitecture-b10775"
  Write-Host "Construction locale de llama.cpp pour CUDA $cudaVersion, sm_$cudaArchitecture. Cette operation unique peut prendre plusieurs minutes."
  & docker build `
    --build-arg "CUDA_DEVEL_IMAGE=$($baseImages[0])" `
    --build-arg "CUDA_RUNTIME_IMAGE=$($baseImages[1])" `
    --build-arg "CUDA_ARCHITECTURES=$cudaArchitecture" `
    --build-arg "LLAMA_CPP_GIT_REF=67a17c17caa95742186f8b1ecadd1b5abd6d5ebb" `
    -t $localImage -f $dockerfile $InstallDir
  if ($LASTEXITCODE -ne 0 -or -not (Test-AiMonitorLlamaGpuImage -Image $localImage)) { return $null }
  Write-DotEnvValue -Path $EnvPath -Key "LLAMA_CPP_CUDA_VERSION" -Value $cudaVersion
  Write-DotEnvValue -Path $EnvPath -Key "LLAMA_CPP_CUDA_ARCHITECTURE" -Value $cudaArchitecture
  Write-DotEnvValue -Path $EnvPath -Key "LLAMA_CPP_CUDA_DEVEL_IMAGE" -Value $baseImages[0]
  Write-DotEnvValue -Path $EnvPath -Key "LLAMA_CPP_CUDA_RUNTIME_IMAGE" -Value $baseImages[1]
  return $localImage
}

function Set-AiMonitorLlamaCpuProfile {
  param([Parameter(Mandatory = $true)][string]$EnvPath)
  Write-DotEnvValue -Path $EnvPath -Key "LLAMA_CPP_RUNTIME_PROFILE" -Value "cpu"
  Write-DotEnvValue -Path $EnvPath -Key "LLAMA_CPP_IMAGE" -Value "ghcr.io/ggml-org/llama.cpp:server@sha256:fcca4dac388066ca93db561751e8caf5fc7d46d9df5f00a7422026db68468e31"
  Write-DotEnvValue -Path $EnvPath -Key "LLAMA_CPP_ACCELERATOR" -Value "cpu"
  Write-DotEnvValue -Path $EnvPath -Key "LLAMA_CPP_GPU_LAYERS" -Value "0"
  Write-DotEnvValue -Path $EnvPath -Key "LLAMA_CPP_FLASH_ATTN" -Value "off"
}

function Set-AiMonitorLlamaGpuProfile {
  param(
    [Parameter(Mandatory = $true)][string]$EnvPath,
    [Parameter(Mandatory = $true)][string]$Image
  )
  Write-DotEnvValue -Path $EnvPath -Key "LLAMA_CPP_RUNTIME_PROFILE" -Value "nvidia"
  Write-DotEnvValue -Path $EnvPath -Key "LLAMA_CPP_IMAGE" -Value $Image
  Write-DotEnvValue -Path $EnvPath -Key "LLAMA_CPP_ACCELERATOR" -Value "cuda"
  Write-DotEnvValue -Path $EnvPath -Key "LLAMA_CPP_GPU_LAYERS" -Value "99"
  Write-DotEnvValue -Path $EnvPath -Key "LLAMA_CPP_FLASH_ATTN" -Value "on"
  Write-DotEnvValue -Path $EnvPath -Key "NVIDIA_VISIBLE_DEVICES" -Value "all"
}

function Protect-AiMonitorSensitiveFile {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }

  $acl = [Security.AccessControl.FileSecurity]::new()
  $acl.SetAccessRuleProtection($true, $false)
  $allow = [Security.AccessControl.AccessControlType]::Allow
  $inheritance = [Security.AccessControl.InheritanceFlags]::None
  $propagation = [Security.AccessControl.PropagationFlags]::None
  $fullControl = [Security.AccessControl.FileSystemRights]::FullControl
  $identities = @(
    [Security.Principal.WindowsIdentity]::GetCurrent().User,
    [Security.Principal.SecurityIdentifier]::new('S-1-5-18'),
    [Security.Principal.SecurityIdentifier]::new('S-1-5-32-544')
  )
  foreach ($identity in $identities) {
    $rule = [Security.AccessControl.FileSystemAccessRule]::new(
      $identity,
      $fullControl,
      $inheritance,
      $propagation,
      $allow
    )
    $acl.AddAccessRule($rule) | Out-Null
  }
  Set-Acl -LiteralPath $Path -AclObject $acl
}

function Assert-AiMonitorGhcrPrivateImagesAccess {
  param(
    [Parameter(Mandatory = $true)][string]$Owner,
    [Parameter(Mandatory = $true)][string]$Reference,
    [Parameter(Mandatory = $true)][string]$GithubUser,
    [Parameter(Mandatory = $true)][string]$GithubToken
  )

  $basicBytes = [Text.Encoding]::ASCII.GetBytes("${GithubUser}:${GithubToken}")
  $basic = [Convert]::ToBase64String($basicBytes)
  foreach ($imageName in @('ai-deep-monitor-api', 'ai-deep-monitor-frontend')) {
    try {
      $scope = "repository:${Owner}/${imageName}:pull"
      $tokenUri = "https://ghcr.io/token?service=ghcr.io&scope=$([uri]::EscapeDataString($scope))"
      $tokenResponse = Invoke-RestMethod -Uri $tokenUri -Method Get -Headers @{ Authorization = "Basic $basic" }
      if (-not $tokenResponse.token) { throw 'Jeton de registre absent.' }
      $headers = @{
        Authorization = "Bearer $($tokenResponse.token)"
        Accept = 'application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json'
      }
      Invoke-WebRequest -UseBasicParsing -Uri "https://ghcr.io/v2/${Owner}/${imageName}/manifests/${Reference}" -Method Get -Headers $headers | Out-Null
    } catch {
      throw "Le compte ou token fourni ne peut pas lire ${Owner}/${imageName}:${Reference}. Utilisez un token limite a read:packages et autorise pour le depot prive."
    }
  }
}

function Resolve-AiMonitorLlamaRuntime {
  param(
    [Parameter(Mandatory = $true)][string]$EnvPath,
    [Parameter(Mandatory = $true)][string]$InstallDir,
    [ValidateSet("", "auto", "cpu", "nvidia", "jetson")][string]$RequestedProfile = "",
    [switch]$RequireGpu,
    [switch]$Redetect
  )
  $runtime = Read-DotEnv -Path $EnvPath
  $profile = [string]$runtime["LLAMA_CPP_RUNTIME_PROFILE"]
  $source = if ($runtime["LLAMA_CPP_PROFILE_SOURCE"]) { [string]$runtime["LLAMA_CPP_PROFILE_SOURCE"] } else { "auto" }
  if ($RequestedProfile) {
    $profile = $RequestedProfile
    $source = if ($profile -eq "auto") { "auto" } else { "manual" }
  }
  if ($Redetect) { $profile = "auto"; $source = "auto" }
  if ($profile -eq "jetson") { throw "Le profil Jetson doit etre configure depuis l'installateur Linux/Jetson." }
  if ($profile -eq "cpu") {
    Set-AiMonitorLlamaCpuProfile -EnvPath $EnvPath
    Write-DotEnvValue -Path $EnvPath -Key "LLAMA_CPP_PROFILE_SOURCE" -Value $source
    return
  }
  $hasNvidia = $false
  if (Get-Command nvidia-smi -ErrorAction SilentlyContinue) {
    & nvidia-smi | Out-Null
    $hasNvidia = $LASTEXITCODE -eq 0
  }
  if ($profile -eq "auto" -and -not $hasNvidia) {
    if ($RequireGpu) { throw "GPU NVIDIA requis mais aucun pilote utilisable n'a ete detecte." }
    Set-AiMonitorLlamaCpuProfile -EnvPath $EnvPath
    Write-DotEnvValue -Path $EnvPath -Key "LLAMA_CPP_PROFILE_SOURCE" -Value "auto"
    Write-Warning "Aucun GPU NVIDIA utilisable detecte: llama.cpp fonctionnera sur CPU."
    return
  }
  if ($profile -notin @("auto", "nvidia")) { throw "Profil llama.cpp invalide: $profile" }
  $image = [string]$runtime["LLAMA_CPP_IMAGE"]
  if (-not $image -or $image -match "/llama\.cpp:server@") {
    $image = "ghcr.io/ggml-org/llama.cpp:server-cuda@sha256:8557e3d273aa6010d46f355e826348b691ba3ddffccae8eaf0150596bbc3ec42"
  }
  if (Test-AiMonitorLlamaGpuImage -Image $image) {
    Set-AiMonitorLlamaGpuProfile -EnvPath $EnvPath -Image $image
    Write-DotEnvValue -Path $EnvPath -Key "LLAMA_CPP_PROFILE_SOURCE" -Value $source
    return
  }
  $autoBuild = if ($runtime["LLAMA_CPP_AUTO_BUILD_CUDA"]) { [string]$runtime["LLAMA_CPP_AUTO_BUILD_CUDA"] } else { "true" }
  if ($autoBuild -eq "true" -and (Test-AiMonitorGpuRuntime -Image $image)) {
    $localImage = Build-AiMonitorLlamaCudaImage -EnvPath $EnvPath -InstallDir $InstallDir
    if ($localImage) {
      Set-AiMonitorLlamaGpuProfile -EnvPath $EnvPath -Image $localImage
      Write-DotEnvValue -Path $EnvPath -Key "LLAMA_CPP_PROFILE_SOURCE" -Value $source
      return
    }
  }
  if ($RequireGpu -or $source -eq "manual") { throw "Le profil GPU NVIDIA a ete demande mais aucune image llama.cpp compatible n'a pu etre validee." }
  Set-AiMonitorLlamaCpuProfile -EnvPath $EnvPath
  Write-DotEnvValue -Path $EnvPath -Key "LLAMA_CPP_PROFILE_SOURCE" -Value "auto"
  Write-Warning "CUDA est present mais incompatible avec les images testees: repli controle sur CPU."
}

function Invoke-AiMonitorComposePull {
  param(
    [Parameter(Mandatory = $true)][string]$ComposePath,
    [Parameter(Mandatory = $true)][string]$EnvPath
  )
  $runtime = Read-DotEnv -Path $EnvPath
  $services = if ([string]$runtime["LLAMA_CPP_IMAGE"] -like "local/*") {
    @("pull", "mysql", "sandbox", "api", "collector", "frontend")
  } else {
    @("pull")
  }
  Invoke-AiMonitorCompose -ComposePath $ComposePath -EnvPath $EnvPath -CommandArguments $services
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
  param(
    [Parameter(Mandatory = $true)][string]$InstallDir,
    [switch]$Required
  )

  function Stop-AgentInstallation {
    param([string]$Message)
    if ($Required) { throw $Message }
    Write-Warning $Message
  }

  $installer = Join-Path $InstallDir "host_terminal_agent\install_windows_task.ps1"
  if (-not (Test-Path -LiteralPath $installer -PathType Leaf)) {
    Stop-AgentInstallation "Agent terminal hote absent du kit."
    return
  }
  if (-not (Get-Command python.exe -ErrorAction SilentlyContinue)) {
    if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
      Stop-AgentInstallation "Python 3 est requis par le terminal hote et winget est indisponible."
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
    Stop-AgentInstallation "Python 3 n'est pas disponible; installez-le puis relancez la reparation."
    return
  }
  try {
    & $installer
    if (-not (Test-AiMonitorHostTerminalAgent -InstallDir $InstallDir -TimeoutSeconds 15)) {
      throw "l'agent a ete lance mais aucun signal valide n'a ete recu dans les 15 secondes."
    }
  } catch {
    Stop-AgentInstallation "Le terminal hote n'est pas operationnel: $($_.Exception.Message)"
  }
}

function Test-AiMonitorHostTerminalAgent {
  param(
    [Parameter(Mandatory = $true)][string]$InstallDir,
    [ValidateRange(0, 120)][int]$TimeoutSeconds = 0
  )

  $jobsDir = Join-Path $InstallDir "host_terminal_jobs"
  $statusPath = Join-Path $jobsDir "status.json"
  $keyPath = Join-Path $jobsDir ".agent-key"
  $deadline = [DateTimeOffset]::UtcNow.AddSeconds($TimeoutSeconds)

  do {
    if ((Test-Path -LiteralPath $statusPath -PathType Leaf) -and
        (Test-Path -LiteralPath $keyPath -PathType Leaf)) {
      try {
        $envelope = Get-Content -LiteralPath $statusPath -Raw | ConvertFrom-Json
        $lastSeen = [double]$envelope.payload.last_seen
        $age = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - $lastSeen
        if ($envelope.signature -and $envelope.payload.available -eq $true -and $age -ge 0 -and $age -le 15) {
          return $true
        }
      } catch {
        # L'agent peut etre en train de remplacer atomiquement le fichier.
      }
    }
    if ([DateTimeOffset]::UtcNow -lt $deadline) {
      Start-Sleep -Seconds 1
    }
  } while ([DateTimeOffset]::UtcNow -lt $deadline)

  return $false
}
