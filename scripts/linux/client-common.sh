#!/usr/bin/env bash

set -Eeuo pipefail

export DEFAULT_APP_VERSION="v0.1.22"
export DOCKER_PLATFORM=""
LLAMA_CPP_DEFAULT_CPU_IMAGE='ghcr.io/ggml-org/llama.cpp:server@sha256:fcca4dac388066ca93db561751e8caf5fc7d46d9df5f00a7422026db68468e31'
LLAMA_CPP_DEFAULT_CUDA_IMAGE='ghcr.io/ggml-org/llama.cpp:server-cuda@sha256:8557e3d273aa6010d46f355e826348b691ba3ddffccae8eaf0150596bbc3ec42'
DOCKER_CMD=(docker)
SUDO_CMD=()

log() {
  printf '[AI Deep Monitor] %s\n' "$*"
}

warn() {
  printf '[AI Deep Monitor] ATTENTION: %s\n' "$*" >&2
}

die() {
  printf '[AI Deep Monitor] ERREUR: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Commande introuvable: $1"
}

configure_sudo() {
  if (( EUID == 0 )); then
    SUDO_CMD=()
  elif command -v sudo >/dev/null 2>&1; then
    SUDO_CMD=(sudo)
  else
    die "L'installation de Docker exige root ou la commande sudo."
  fi
}

run_root() {
  "${SUDO_CMD[@]}" "$@"
}

ensure_python3() {
  command -v python3 >/dev/null 2>&1 && return 0
  configure_sudo
  log "Python 3 est requis par le terminal hote; installation automatique..."
  if command -v apt-get >/dev/null 2>&1; then
    run_root apt-get update
    run_root apt-get install -y python3
  elif command -v dnf >/dev/null 2>&1; then
    run_root dnf -y install python3
  elif command -v yum >/dev/null 2>&1; then
    run_root yum -y install python3
  else
    warn "Gestionnaire de paquets non pris en charge; installez Python 3 puis relancez."
    return 1
  fi
  command -v python3 >/dev/null 2>&1
}

install_docker_linux() {
  [[ "$(uname -s)" == "Linux" ]] || die "L'installation automatique de Docker est reservee a Linux."
  [[ -r /etc/os-release ]] || die "Distribution Linux non identifiable: /etc/os-release absent."

  # shellcheck disable=SC1091
  . /etc/os-release
  local distro="${ID,,}"
  local codename="${VERSION_CODENAME:-}"
  local repo_distro=""

  configure_sudo
  log "Docker est absent. Installation depuis le depot officiel Docker..."

  case "$distro" in
    ubuntu|debian|linuxmint)
      if [[ "$distro" == "linuxmint" ]]; then
        repo_distro="ubuntu"
        codename="${UBUNTU_CODENAME:-$codename}"
      else
        repo_distro="$distro"
      fi
      [[ -n "$codename" ]] || die "Nom de version Linux introuvable pour configurer le depot Docker."

      run_root apt-get update
      run_root apt-get install -y ca-certificates curl
      run_root install -m 0755 -d /etc/apt/keyrings
      curl -fsSL "https://download.docker.com/linux/${repo_distro}/gpg" |
        "${SUDO_CMD[@]}" tee /etc/apt/keyrings/docker.asc >/dev/null
      run_root chmod a+r /etc/apt/keyrings/docker.asc

      printf 'deb [arch=%s signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/%s %s stable\n' \
        "$(dpkg --print-architecture)" "$repo_distro" "$codename" |
        "${SUDO_CMD[@]}" tee /etc/apt/sources.list.d/docker.list >/dev/null

      run_root apt-get update
      run_root apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
      ;;
    fedora|rhel|centos|rocky|almalinux)
      repo_distro="centos"
      [[ "$distro" == "fedora" ]] && repo_distro="fedora"
      if command -v dnf >/dev/null 2>&1; then
        run_root dnf -y install dnf-plugins-core curl ca-certificates
        if ! run_root dnf config-manager --add-repo "https://download.docker.com/linux/${repo_distro}/docker-ce.repo"; then
          run_root dnf config-manager addrepo \
            --from-repofile="https://download.docker.com/linux/${repo_distro}/docker-ce.repo"
        fi
        run_root dnf -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
      else
        require_command yum
        run_root yum -y install yum-utils curl ca-certificates
        run_root yum-config-manager --add-repo "https://download.docker.com/linux/${repo_distro}/docker-ce.repo"
        run_root yum -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
      fi
      ;;
    *)
      die "Distribution non prise en charge automatiquement (${distro}). Installez Docker Engine et le plugin Compose, puis relancez le script."
      ;;
  esac

  if command -v systemctl >/dev/null 2>&1; then
    run_root systemctl enable --now docker
  else
    warn "systemctl absent. Demarrez le service Docker avant de poursuivre."
  fi

  if (( EUID != 0 )); then
    run_root usermod -aG docker "${SUDO_USER:-$USER}" || true
    warn "Votre compte a ete ajoute au groupe docker. Une reconnexion sera necessaire pour utiliser Docker sans sudo."
  fi
}

ensure_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    install_docker_linux
  fi

  if ! docker info >/dev/null 2>&1; then
    configure_sudo
    if command -v systemctl >/dev/null 2>&1; then
      run_root systemctl start docker || true
    fi
  fi

  if docker info >/dev/null 2>&1; then
    DOCKER_CMD=(docker)
  else
    configure_sudo
    if "${SUDO_CMD[@]}" docker info >/dev/null 2>&1; then
      DOCKER_CMD=("${SUDO_CMD[@]}" docker)
    else
      die "Docker est installe mais son moteur ne repond pas."
    fi
  fi

  "${DOCKER_CMD[@]}" compose version >/dev/null 2>&1 ||
    die "Le plugin Docker Compose v2 est absent."

  detect_docker_platform
}

docker_exec() {
  "${DOCKER_CMD[@]}" "$@"
}

docker_registry_login() {
  local registry="$1"
  local username="$2"
  local token="$3"
  local user_config="${HOME}/.docker"

  [[ -n "$username" && -n "$token" ]] || die "Identifiants GHCR incomplets."
  mkdir -p "$user_config"
  chmod 700 "$user_config" 2>/dev/null || true

  # `docker login` does not need access to the daemon. Always authenticate the
  # non-root user as well, because the protected host agent runs with that
  # profile even when Compose itself has to use sudo on this machine.
  printf '%s' "$token" |
    DOCKER_CONFIG="$user_config" docker login "$registry" -u "$username" --password-stdin

  if [[ "${DOCKER_CMD[*]}" != "docker" ]]; then
    # Keep the privileged Docker client usable for the current installation
    # session while the user profile remains the reference for the host agent.
    printf '%s' "$token" |
      docker_exec login "$registry" -u "$username" --password-stdin
  fi
}

compose_exec() {
  docker_exec compose "$@"
}

llama_compose_override() {
  local compose_file="$1"
  local env_file="$2"
  local profile
  local install_dir
  profile="$(read_env_value "$env_file" LLAMA_CPP_RUNTIME_PROFILE)"
  install_dir="$(dirname "$compose_file")"
  case "${profile,,}" in
    nvidia)
      printf '%s\n' "${install_dir}/docker-compose.accel.nvidia.yml"
      ;;
    jetson)
      printf '%s\n' "${install_dir}/docker-compose.accel.jetson.yml"
      ;;
  esac
}

compose_runtime_exec() {
  local project="$1"
  local compose_file="$2"
  local env_file="$3"
  local override_file
  shift 3
  override_file="$(llama_compose_override "$compose_file" "$env_file")"
  if [[ -n "$override_file" ]]; then
    [[ -f "$override_file" ]] || die "Override llama.cpp absent: ${override_file}"
    compose_exec -p "$project" -f "$compose_file" -f "$override_file" --env-file "$env_file" "$@"
  else
    compose_exec -p "$project" -f "$compose_file" --env-file "$env_file" "$@"
  fi
}

compose_runtime_pull() {
  local project="$1"
  local compose_file="$2"
  local env_file="$3"
  local image
  image="$(read_env_value "$env_file" LLAMA_CPP_IMAGE)"
  if [[ "$image" == local/* ]]; then
    compose_runtime_exec "$project" "$compose_file" "$env_file" \
      pull mysql sandbox api collector frontend
  else
    compose_runtime_exec "$project" "$compose_file" "$env_file" pull
  fi
}

normalize_docker_arch() {
  case "${1,,}" in
    amd64|x86_64|x64)
      printf 'amd64\n'
      ;;
    arm64|arm64/v8|aarch64)
      printf 'arm64\n'
      ;;
    *)
      return 1
      ;;
  esac
}

resolve_docker_platform() {
  local os_type="${1,,}"
  local architecture="$2"
  local normalized_arch

  [[ "$os_type" == "linux" ]] || return 2
  normalized_arch="$(normalize_docker_arch "$architecture")" || return 3
  printf 'linux/%s\n' "$normalized_arch"
}

detect_host_platform() {
  local host_os
  local host_arch

  host_os="$(uname -s 2>/dev/null || true)"
  host_arch="$(uname -m 2>/dev/null || true)"
  [[ "${host_os,,}" == "linux" ]] ||
    die "Le script Linux exige un hote Linux. Sous Windows, utilisez install-client.ps1."

  DOCKER_PLATFORM="$(resolve_docker_platform linux "$host_arch")" ||
    die "Architecture hote non prise en charge: ${host_arch:-inconnue}. Architectures supportees: amd64 et arm64."
  export DOCKER_PLATFORM
}

detect_docker_platform() {
  local docker_info
  local os_type
  local architecture
  local status

  docker_info="$(docker_exec info --format '{{.OSType}}|{{.Architecture}}' 2>/dev/null)" ||
    die "Impossible d'identifier la plateforme du moteur Docker."
  IFS='|' read -r os_type architecture <<<"$docker_info"

  set +e
  DOCKER_PLATFORM="$(resolve_docker_platform "$os_type" "$architecture")"
  status=$?
  set -e
  case "$status" in
    0)
      ;;
    2)
      die "Docker utilise les conteneurs ${os_type:-inconnus}. AI Deep Monitor exige les conteneurs Linux. Sous Docker Desktop, activez 'Switch to Linux containers' puis relancez."
      ;;
    *)
      die "Architecture Docker non prise en charge: ${architecture:-inconnue}. Architectures supportees: amd64 et arm64 (Jetson)."
      ;;
  esac

  export DOCKER_PLATFORM
  log "Plateforme Docker detectee: ${DOCKER_PLATFORM}."
}

new_secret() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 24
  else
    od -An -N24 -tx1 /dev/urandom | tr -d ' \n'
  fi
}

read_env_value() {
  local file="$1"
  local key="$2"
  [[ -f "$file" ]] || return 0
  awk -v wanted="$key" '
    /^[[:space:]]*#/ { next }
    {
      pos = index($0, "=")
      if (pos == 0) next
      key = substr($0, 1, pos - 1)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
      if (key == wanted) {
        value = substr($0, pos + 1)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
        gsub(/^["'\'']|["'\'']$/, "", value)
        result = value
      }
    }
    END { if (result != "") print result }
  ' "$file"
}

write_env_value() {
  local file="$1"
  local key="$2"
  local value="$3"
  local tmp
  tmp="$(mktemp)"
  awk -v wanted="$key" -v replacement="$value" '
    BEGIN { found = 0 }
    {
      pos = index($0, "=")
      current = pos ? substr($0, 1, pos - 1) : ""
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", current)
      if (current == wanted) {
        print wanted "=" replacement
        found = 1
      } else {
        print
      }
    }
    END {
      if (!found) print wanted "=" replacement
    }
  ' "$file" >"$tmp"
  mv "$tmp" "$file"
  chmod 600 "$file"
}

remove_env_value() {
  local file="$1"
  local key="$2"
  local tmp
  [[ -f "$file" ]] || return 0
  tmp="$(mktemp)"
  awk -v unwanted="$key" '
    index($0, unwanted "=") != 1 { print }
  ' "$file" >"$tmp"
  mv -f "$tmp" "$file"
}

AUTH_CONFIG_CHANGED=false
GENERATED_BOOTSTRAP_PASSWORD=""
LLAMA_CPP_CONFIG_CHANGED=false

ensure_auth_config() {
  local env_file="$1"
  local secret
  local key
  local value

  secret="$(read_env_value "$env_file" AUTH_SECRET_KEY)"
  if (( ${#secret} < 32 )); then
    write_env_value "$env_file" AUTH_SECRET_KEY "$(new_secret)"
    AUTH_CONFIG_CHANGED=true
  fi

  if [[ -z "$(read_env_value "$env_file" AUTH_BOOTSTRAP_USERNAME)" ]]; then
    write_env_value "$env_file" AUTH_BOOTSTRAP_USERNAME admin
    AUTH_CONFIG_CHANGED=true
  fi

  if [[ -z "$(read_env_value "$env_file" AUTH_BOOTSTRAP_PASSWORD)" ]]; then
    GENERATED_BOOTSTRAP_PASSWORD="Adm1-$(new_secret)"
    write_env_value "$env_file" AUTH_BOOTSTRAP_PASSWORD "$GENERATED_BOOTSTRAP_PASSWORD"
    AUTH_CONFIG_CHANGED=true
  fi

  while IFS='=' read -r key value; do
    if [[ -z "$(read_env_value "$env_file" "$key")" ]]; then
      write_env_value "$env_file" "$key" "$value"
      AUTH_CONFIG_CHANGED=true
    fi
  done <<'EOF'
AUTH_ACCESS_TOKEN_MINUTES=15
AUTH_REFRESH_TOKEN_DAYS=7
AUTH_MAX_FAILED_ATTEMPTS=5
AUTH_LOCK_MINUTES=15
AUTH_COOKIE_SECURE=false
AUTH_COOKIE_SAMESITE=lax
TELEMETRY_RAW_RETENTION_DAYS=7
TELEMETRY_ROLLUP_RETENTION_DAYS=365
EOF
}

ensure_llama_cpp_config() {
  local env_file="$1"
  local key
  local value

  while IFS='=' read -r key value; do
    if [[ -z "$(read_env_value "$env_file" "$key")" ]]; then
      write_env_value "$env_file" "$key" "$value"
      LLAMA_CPP_CONFIG_CHANGED=true
    fi
  done <<'EOF'
LLAMA_CPP_RUNTIME_PROFILE=auto
LLAMA_CPP_PROFILE_SOURCE=auto
LLAMA_CPP_IMAGE=ghcr.io/ggml-org/llama.cpp:server@sha256:fcca4dac388066ca93db561751e8caf5fc7d46d9df5f00a7422026db68468e31
LLAMA_CPP_HF_REPO=bartowski/Llama-3.2-3B-Instruct-GGUF:Q4_K_M
LLAMA_CPP_MODEL=Llama-3.2-3B-Instruct-Q4_K_M
LLAMA_CPP_TEMPERATURE=0.2
LLAMA_CPP_MAX_TOKENS=512
LLAMA_CPP_TIMEOUT_SECONDS=300
LLAMA_CPP_CONTEXT_SIZE=8192
LLAMA_CPP_PARALLEL=2
LLAMA_CPP_GPU_LAYERS=0
LLAMA_CPP_ACCELERATOR=cpu
LLAMA_CPP_FLASH_ATTN=off
LLAMA_CPP_AUTO_BUILD_CUDA=true
NVIDIA_VISIBLE_DEVICES=all
EOF

  for key in OLLAMA_IMAGE OLLAMA_MODEL OLLAMA_FALLBACK_MODEL OLLAMA_TEMPERATURE OLLAMA_NUM_PREDICT; do
    if [[ -n "$(read_env_value "$env_file" "$key")" ]]; then
      remove_env_value "$env_file" "$key"
      LLAMA_CPP_CONFIG_CHANGED=true
    fi
  done
}

llama_is_jetson() {
  [[ -f /etc/nv_tegra_release ]] && return 0
  if [[ -r /proc/device-tree/model ]]; then
    tr -d '\000' </proc/device-tree/model 2>/dev/null | grep -qi 'jetson' && return 0
  fi
  return 1
}

llama_cuda_version() {
  local version=""
  if [[ -r /usr/local/cuda/version.json ]]; then
    version="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([0-9][0-9]*\.[0-9][0-9]*\).*/\1/p' /usr/local/cuda/version.json | head -n 1)"
  fi
  if [[ -z "$version" ]] && command -v nvcc >/dev/null 2>&1; then
    version="$(nvcc --version 2>/dev/null | sed -n 's/.*release \([0-9][0-9]*\.[0-9][0-9]*\).*/\1/p' | tail -n 1)"
  fi
  if [[ -z "$version" ]] && command -v nvidia-smi >/dev/null 2>&1; then
    version="$(nvidia-smi 2>/dev/null | sed -n 's/.*CUDA Version:[[:space:]]*\([0-9][0-9]*\.[0-9][0-9]*\).*/\1/p' | head -n 1)"
  fi
  printf '%s\n' "$version"
}

llama_cuda_architecture() {
  local model=""
  local compute=""
  if [[ -r /proc/device-tree/model ]]; then
    model="$(tr -d '\000' </proc/device-tree/model 2>/dev/null || true)"
    case "${model,,}" in
      *orin*) printf '87\n'; return 0 ;;
      *xavier*) printf '72\n'; return 0 ;;
      *tx2*) printf '62\n'; return 0 ;;
      *nano*) printf '53\n'; return 0 ;;
    esac
  fi
  if command -v nvidia-smi >/dev/null 2>&1; then
    compute="$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | head -n 1 | tr -d '. ')"
  fi
  [[ "$compute" =~ ^[0-9]+$ ]] || return 1
  printf '%s\n' "$compute"
}

llama_cuda_base_images() {
  local version="$1"
  case "$version" in
    13.0) printf '%s|%s\n' 'nvidia/cuda:13.0.1-devel-ubuntu24.04' 'nvidia/cuda:13.0.1-runtime-ubuntu24.04' ;;
    12.9) printf '%s|%s\n' 'nvidia/cuda:12.9.1-devel-ubuntu24.04' 'nvidia/cuda:12.9.1-runtime-ubuntu24.04' ;;
    12.8) printf '%s|%s\n' 'nvidia/cuda:12.8.1-devel-ubuntu24.04' 'nvidia/cuda:12.8.1-runtime-ubuntu24.04' ;;
    12.6) printf '%s|%s\n' 'nvidia/cuda:12.6.3-devel-ubuntu24.04' 'nvidia/cuda:12.6.3-runtime-ubuntu24.04' ;;
    12.4) printf '%s|%s\n' 'nvidia/cuda:12.4.1-devel-ubuntu22.04' 'nvidia/cuda:12.4.1-runtime-ubuntu22.04' ;;
    12.2) printf '%s|%s\n' 'nvidia/cuda:12.2.2-devel-ubuntu22.04' 'nvidia/cuda:12.2.2-runtime-ubuntu22.04' ;;
    12.1) printf '%s|%s\n' 'nvidia/cuda:12.1.1-devel-ubuntu22.04' 'nvidia/cuda:12.1.1-runtime-ubuntu22.04' ;;
    11.8) printf '%s|%s\n' 'nvidia/cuda:11.8.0-devel-ubuntu22.04' 'nvidia/cuda:11.8.0-runtime-ubuntu22.04' ;;
    11.4) printf '%s|%s\n' 'nvidia/cuda:11.4.3-devel-ubuntu20.04' 'nvidia/cuda:11.4.3-runtime-ubuntu20.04' ;;
    *) return 1 ;;
  esac
}

llama_gpu_probe_candidate() {
  local profile="$1"
  local image="${2:-}"

  # L'image CUDA generique est volumineuse et ne correspond pas forcement a
  # CUDA/JetPack sur ARM64. Sur Jetson, la telecharger avant la construction
  # locale ajoute plusieurs gigaoctets et peut rester bloquee sans rien valider.
  # Une image locale deja construite ou une image personnalisee reste testee.
  if [[ "$profile" == jetson ]]; then
    case "$image" in
      ""|*'/llama.cpp:server@'*|*'/llama.cpp:server-cuda@'*)
        return 1
        ;;
    esac
  fi

  if [[ -z "$image" || "$image" == *'/llama.cpp:server@'* ]]; then
    image="$LLAMA_CPP_DEFAULT_CUDA_IMAGE"
  fi
  printf '%s\n' "$image"
}

llama_gpu_probe() {
  local profile="$1"
  local image="$2"
  local output=""
  local -a gpu_args
  if [[ "$profile" == "jetson" ]]; then
    gpu_args=(--runtime nvidia -e NVIDIA_VISIBLE_DEVICES=all -e NVIDIA_DRIVER_CAPABILITIES=compute,utility -e NVIDIA_DISABLE_REQUIRE=1)
  else
    gpu_args=(--gpus all)
  fi
  output="$(docker_exec run --rm "${gpu_args[@]}" "$image" --list-devices 2>&1)" || {
    warn "$output"
    return 1
  }
  printf '%s\n' "$output"
  grep -q 'CUDA0:' <<<"$output"
}

llama_gpu_runtime_available() {
  local profile="$1"
  local image="$2"
  local -a gpu_args
  if [[ "$profile" == "jetson" ]]; then
    gpu_args=(--runtime nvidia -e NVIDIA_VISIBLE_DEVICES=all -e NVIDIA_DISABLE_REQUIRE=1)
  else
    gpu_args=(--gpus all)
  fi
  docker_exec run --rm "${gpu_args[@]}" --entrypoint /bin/true "$image" >/dev/null 2>&1
}

llama_jetson_runtime_available() {
  local runtimes
  llama_is_jetson || return 1
  runtimes="$(docker_exec info --format '{{json .Runtimes}}' 2>/dev/null || true)"
  grep -q '"nvidia"' <<<"$runtimes"
}

llama_build_cuda_image() {
  local env_file="$1"
  local profile="$2"
  local install_dir
  local dockerfile
  local cuda_version
  local cuda_arch
  local configured_devel
  local configured_runtime
  local mapped
  local devel_image
  local runtime_image
  local local_image
  local build_jobs
  install_dir="$(dirname "$env_file")"
  dockerfile="${install_dir}/Dockerfile.llama-cuda"
  [[ -f "$dockerfile" ]] || { warn "Dockerfile CUDA local absent: ${dockerfile}"; return 1; }
  cuda_version="$(llama_cuda_version)"
  cuda_arch="$(llama_cuda_architecture || true)"
  [[ -n "$cuda_version" ]] || { warn 'Version CUDA hote introuvable.'; return 1; }
  [[ -n "$cuda_arch" ]] || { warn 'Architecture CUDA du GPU introuvable.'; return 1; }

  configured_devel="$(read_env_value "$env_file" LLAMA_CPP_CUDA_DEVEL_IMAGE)"
  configured_runtime="$(read_env_value "$env_file" LLAMA_CPP_CUDA_RUNTIME_IMAGE)"
  if [[ -n "$configured_devel" && -n "$configured_runtime" ]]; then
    devel_image="$configured_devel"
    runtime_image="$configured_runtime"
  else
    mapped="$(llama_cuda_base_images "$cuda_version" || true)"
    [[ -n "$mapped" ]] || {
      warn "CUDA ${cuda_version} n'a pas encore de base automatique. Definissez LLAMA_CPP_CUDA_DEVEL_IMAGE et LLAMA_CPP_CUDA_RUNTIME_IMAGE."
      return 1
    }
    IFS='|' read -r devel_image runtime_image <<<"$mapped"
  fi

  local_image="local/ai-deep-monitor-llama-cpp:cuda-${cuda_version}-sm${cuda_arch}-b10775"
  build_jobs="$(read_env_value "$env_file" LLAMA_CPP_CUDA_BUILD_JOBS)"
  build_jobs="${build_jobs:-4}"
  [[ "$build_jobs" =~ ^[1-9][0-9]*$ ]] || {
    warn "LLAMA_CPP_CUDA_BUILD_JOBS invalide: ${build_jobs}."
    return 1
  }
  log "Construction locale de llama.cpp pour CUDA ${cuda_version}, sm_${cuda_arch}. Cette operation unique peut prendre plusieurs minutes."
  if ! docker_exec build \
    --build-arg "CUDA_DEVEL_IMAGE=${devel_image}" \
    --build-arg "CUDA_RUNTIME_IMAGE=${runtime_image}" \
    --build-arg "CUDA_ARCHITECTURES=${cuda_arch}" \
    --build-arg "BUILD_JOBS=${build_jobs}" \
    --build-arg 'LLAMA_CPP_GIT_REF=67a17c17caa95742186f8b1ecadd1b5abd6d5ebb' \
    -t "$local_image" \
    -f "$dockerfile" "$install_dir"; then
    warn "La construction llama.cpp CUDA ${cuda_version} a echoue."
    return 1
  fi
  llama_gpu_probe "$profile" "$local_image" || return 1
  write_env_value "$env_file" LLAMA_CPP_IMAGE "$local_image"
  write_env_value "$env_file" LLAMA_CPP_CUDA_VERSION "$cuda_version"
  write_env_value "$env_file" LLAMA_CPP_CUDA_ARCHITECTURE "$cuda_arch"
  write_env_value "$env_file" LLAMA_CPP_CUDA_DEVEL_IMAGE "$devel_image"
  write_env_value "$env_file" LLAMA_CPP_CUDA_RUNTIME_IMAGE "$runtime_image"
}

llama_set_cpu_profile() {
  local env_file="$1"
  write_env_value "$env_file" LLAMA_CPP_RUNTIME_PROFILE cpu
  write_env_value "$env_file" LLAMA_CPP_IMAGE "$LLAMA_CPP_DEFAULT_CPU_IMAGE"
  write_env_value "$env_file" LLAMA_CPP_ACCELERATOR cpu
  write_env_value "$env_file" LLAMA_CPP_GPU_LAYERS 0
  write_env_value "$env_file" LLAMA_CPP_FLASH_ATTN off
}

llama_set_gpu_profile() {
  local env_file="$1"
  local profile="$2"
  local image="$3"
  write_env_value "$env_file" LLAMA_CPP_RUNTIME_PROFILE "$profile"
  write_env_value "$env_file" LLAMA_CPP_IMAGE "$image"
  write_env_value "$env_file" LLAMA_CPP_ACCELERATOR cuda
  write_env_value "$env_file" LLAMA_CPP_GPU_LAYERS 99
  write_env_value "$env_file" LLAMA_CPP_FLASH_ATTN on
  write_env_value "$env_file" NVIDIA_VISIBLE_DEVICES all
}

configure_llama_cpp_runtime() {
  local env_file="$1"
  local requested_profile="${2:-}"
  local require_gpu="${3:-false}"
  local redetect="${4:-false}"
  local profile
  local source
  local image
  local candidate
  local auto_build

  profile="$(read_env_value "$env_file" LLAMA_CPP_RUNTIME_PROFILE)"
  source="$(read_env_value "$env_file" LLAMA_CPP_PROFILE_SOURCE)"
  if [[ -n "$requested_profile" ]]; then
    profile="${requested_profile,,}"
    source=manual
    [[ "$profile" == auto ]] && source=auto
  fi
  [[ "$redetect" == true ]] && profile=auto && source=auto
  case "$profile" in auto|cpu|nvidia|jetson) ;; *) die "Profil llama.cpp invalide: ${profile}" ;; esac

  if [[ "$profile" == cpu ]]; then
    llama_set_cpu_profile "$env_file"
    write_env_value "$env_file" LLAMA_CPP_PROFILE_SOURCE "$source"
    log 'llama.cpp: profil CPU selectionne (aucun GPU Docker requis).'
    return 0
  fi

  if [[ "$profile" == auto ]]; then
    if llama_is_jetson; then
      profile=jetson
    elif command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1; then
      profile=nvidia
    else
      if [[ "$require_gpu" == true ]]; then
        die 'GPU NVIDIA requis mais aucun pilote utilisable n a ete detecte.'
      fi
      llama_set_cpu_profile "$env_file"
      write_env_value "$env_file" LLAMA_CPP_PROFILE_SOURCE auto
      warn 'Aucun GPU NVIDIA utilisable detecte: llama.cpp fonctionnera sur CPU.'
      return 0
    fi
  fi

  image="$(read_env_value "$env_file" LLAMA_CPP_IMAGE)"
  candidate="$(llama_gpu_probe_candidate "$profile" "$image" || true)"
  if [[ -n "$candidate" ]] && llama_gpu_probe "$profile" "$candidate"; then
    llama_set_gpu_profile "$env_file" "$profile" "$candidate"
    write_env_value "$env_file" LLAMA_CPP_PROFILE_SOURCE "$source"
    log "llama.cpp: GPU CUDA valide (${profile})."
    return 0
  fi

  auto_build="$(read_env_value "$env_file" LLAMA_CPP_AUTO_BUILD_CUDA)"
  auto_build="${auto_build:-true}"
  if [[ "$auto_build" == true ]] &&
     { { [[ "$profile" == jetson ]] && llama_jetson_runtime_available; } ||
       { [[ -n "$candidate" ]] && llama_gpu_runtime_available "$profile" "$candidate"; }; } &&
     llama_build_cuda_image "$env_file" "$profile"; then
    image="$(read_env_value "$env_file" LLAMA_CPP_IMAGE)"
    llama_set_gpu_profile "$env_file" "$profile" "$image"
    write_env_value "$env_file" LLAMA_CPP_PROFILE_SOURCE "$source"
    log "llama.cpp: image CUDA locale valide (${profile})."
    return 0
  fi

  if [[ "$require_gpu" == true || "$source" == manual ]]; then
    die "Le profil GPU ${profile} a ete demande mais aucune image llama.cpp compatible n'a pu etre validee."
  fi
  llama_set_cpu_profile "$env_file"
  write_env_value "$env_file" LLAMA_CPP_PROFILE_SOURCE auto
  warn 'CUDA est present mais incompatible avec les images testees: repli controle sur CPU.'
}

print_bootstrap_credentials() {
  [[ -n "$GENERATED_BOOTSTRAP_PASSWORD" ]] || return 0
  printf '\nCompte initial, utilise uniquement si aucun administrateur n existe deja:\n'
  printf '  Utilisateur : admin\n'
  printf '  Mot de passe: %s\n' "$GENERATED_BOOTSTRAP_PASSWORD"
  printf 'Un compte existant conserve son mot de passe actuel.\n\n'
}

port_is_available() {
  local port="$1"
  local endpoint
  local port_hex
  local socket_files=(/proc/net/tcp)

  if command -v ss >/dev/null 2>&1; then
    while read -r endpoint; do
      endpoint="${endpoint##*:}"
      [[ "$endpoint" == "$port" ]] && return 1
    done < <(ss -H -ltn 2>/dev/null | awk '{print $4}')
    return 0
  fi

  if [[ -r /proc/net/tcp ]]; then
    [[ -r /proc/net/tcp6 ]] && socket_files+=(/proc/net/tcp6)
    printf -v port_hex '%04X' "$port"
    if awk -v wanted="$port_hex" '
      FNR > 1 {
        split($2, address, ":")
        if (toupper(address[2]) == wanted && $4 == "0A") {
          found = 1
          exit
        }
      }
      END { exit found ? 0 : 1 }
    ' "${socket_files[@]}"; then
      return 1
    fi
    return 0
  fi

  if command -v python3 >/dev/null 2>&1; then
    python3 - "$port" <<'PY'
import errno
import socket
import sys

sock = socket.socket()
try:
    sock.bind(("0.0.0.0", int(sys.argv[1])))
except OSError as exc:
    if exc.errno in {errno.EACCES, errno.EPERM}:
        raise SystemExit(0)
    raise SystemExit(1)
finally:
    sock.close()
PY
  else
    warn "Impossible de verifier le port ${port}: aucun outil de diagnostic disponible."
    return 0
  fi
}

container_project_name() {
  local container="$1"
  docker_exec inspect \
    --format '{{ index .Config.Labels "com.docker.compose.project" }}' \
    "$container" 2>/dev/null || true
}

container_publishing_port() {
  local port="$1"
  docker_exec ps \
    --filter "publish=${port}" \
    --format '{{.Names}}' 2>/dev/null |
    awk 'NF { print; exit }'
}

port_is_available_for_project() {
  local port="$1"
  local project="$2"
  local owner

  if port_is_available "$port"; then
    return 0
  fi

  owner="$(container_publishing_port "$port")"
  [[ -n "$owner" && "$(container_project_name "$owner")" == "$project" ]]
}

select_runtime_port() {
  local preferred="$1"
  local fallback="$2"
  local project="$3"
  local excluded="${4:-}"
  local port

  for port in "$preferred" "$fallback"; do
    [[ -n "$port" && "$port" != "$excluded" ]] || continue
    if port_is_available_for_project "$port" "$project"; then
      printf '%s\n' "$port"
      return 0
    fi
  done

  for ((port = fallback + 1; port <= fallback + 200 && port <= 65535; port++)); do
    [[ "$port" != "$excluded" ]] || continue
    if port_is_available_for_project "$port" "$project"; then
      printf '%s\n' "$port"
      return 0
    fi
  done

  die "Aucun port disponible entre ${fallback} et $((fallback + 200))."
}

describe_port_owner() {
  local port="$1"
  local owner
  owner="$(container_publishing_port "$port")"
  if [[ -n "$owner" ]]; then
    printf 'conteneur Docker %s' "$owner"
  else
    printf 'un service du systeme'
  fi
}

available_port() {
  local preferred="$1"
  local excluded="${2:-}"
  local port
  for ((port = preferred; port <= preferred + 200 && port <= 65535; port++)); do
    [[ " ${excluded} " == *" ${port} "* ]] && continue
    if port_is_available "$port"; then
      printf '%s\n' "$port"
      return 0
    fi
  done
  die "Aucun port disponible a partir de ${preferred}."
}

show_startup_diagnostics() {
  local project="$1"
  local compose_file="$2"
  local env_file="$3"

  warn "Etat des services:"
  compose_runtime_exec "$project" "$compose_file" "$env_file" ps || true
  warn "Derniers journaux utiles:"
  compose_runtime_exec "$project" "$compose_file" "$env_file" \
    logs --tail=120 mysql sandbox llama-cpp api collector || true
}

project_name_from_dir() {
  basename "$1" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9_-'
}

existing_data_volumes() {
  local project="$1"
  local expected
  expected="${project}_client_(mysql_data|api_data|uploaded_mibs|generated_backups|llama_cpp_cache|ollama_data|sandbox_jobs)"
  docker_exec volume ls --format '{{.Name}}' 2>/dev/null |
    grep -E "^${expected}$" || true
}

wait_for_container() {
  local container="$1"
  local timeout="${2:-180}"
  local elapsed=0
  local status=""
  while (( elapsed < timeout )); do
    status="$(docker_exec inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$container" 2>/dev/null || true)"
    case "$status" in
      healthy|running)
        return 0
        ;;
      unhealthy|exited|dead)
        return 1
        ;;
    esac
    sleep 2
    ((elapsed += 2))
  done
  return 1
}

ghcr_bearer_token() {
  local owner="$1"
  local image="$2"
  local user="$3"
  local token="$4"
  curl -fsS -u "${user}:${token}" \
    "https://ghcr.io/token?scope=repository:${owner}/${image}:pull&service=ghcr.io" |
    sed -n 's/.*"token":"\([^"]*\)".*/\1/p'
}

ghcr_manifest_available() {
  local owner="$1"
  local image="$2"
  local reference="$3"
  local user="$4"
  local token="$5"
  local bearer

  bearer="$(ghcr_bearer_token "$owner" "$image" "$user" "$token")" || return 1
  [[ -n "$bearer" ]] || return 1
  curl -fsS -o /dev/null \
    -H "Authorization: Bearer ${bearer}" \
    -H 'Accept: application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json' \
    "https://ghcr.io/v2/${owner}/${image}/manifests/${reference}"
}

validate_private_images_access() {
  local owner="$1"
  local reference="$2"
  local user="$3"
  local token="$4"
  local image

  for image in ai-deep-monitor-api ai-deep-monitor-frontend; do
    ghcr_manifest_available "$owner" "$image" "$reference" "$user" "$token" ||
      die "Le compte ou token fourni ne peut pas lire ${owner}/${image}:${reference}. Utilisez un token limite a read:packages et autorise pour le depot prive."
  done
}

ghcr_tags() {
  local owner="$1"
  local image="$2"
  local user="$3"
  local token="$4"
  local bearer
  bearer="$(ghcr_bearer_token "$owner" "$image" "$user" "$token")"
  [[ -n "$bearer" ]] || return 1

  local page_url="https://ghcr.io/v2/${owner}/${image}/tags/list?n=100"
  local temp_dir headers_file body_file seen_file tags_file link_header next_path
  temp_dir="$(mktemp -d)"
  headers_file="${temp_dir}/headers"
  body_file="${temp_dir}/body"
  seen_file="${temp_dir}/seen"
  tags_file="${temp_dir}/tags"
  : >"$seen_file"
  : >"$tags_file"

  while [[ -n "$page_url" ]]; do
    if grep -Fqx -- "$page_url" "$seen_file"; then
      rm -rf -- "$temp_dir"
      return 1
    fi
    printf '%s\n' "$page_url" >>"$seen_file"

    curl -fsS -D "$headers_file" -o "$body_file" \
      -H "Authorization: Bearer ${bearer}" "$page_url" || {
        rm -rf -- "$temp_dir"
        return 1
      }
    grep -Eo '"v[0-9]+\.[0-9]+\.[0-9]+"' "$body_file" |
      tr -d '"' >>"$tags_file" || true

    link_header="$(tr -d '\r' <"$headers_file" | sed -n 's/^[Ll]ink:[[:space:]]*//p' | tail -n 1)"
    next_path="$(printf '%s' "$link_header" | sed -n 's/.*<\([^>]*\)>;[[:space:]]*rel="next".*/\1/p')"
    if [[ -z "$next_path" ]]; then
      page_url=""
    elif [[ "$next_path" == http://* || "$next_path" == https://* ]]; then
      page_url="$next_path"
    else
      page_url="https://ghcr.io${next_path}"
    fi
  done

  sort -V -u "$tags_file"
  rm -rf -- "$temp_dir"
}

latest_common_app_version() {
  local owner="$1"
  local user="$2"
  local token="$3"
  local api_versions frontend_versions
  api_versions="$(ghcr_tags "$owner" "ai-deep-monitor-api" "$user" "$token")" ||
    die "Impossible de lire les versions API sur GHCR."
  frontend_versions="$(ghcr_tags "$owner" "ai-deep-monitor-frontend" "$user" "$token")" ||
    die "Impossible de lire les versions frontend sur GHCR."

  comm -12 \
    <(printf '%s\n' "$api_versions" | sort -V) \
    <(printf '%s\n' "$frontend_versions" | sort -V) |
    tail -n 1
}

confirm() {
  local question="$1"
  local assume_yes="${2:-false}"
  local answer
  [[ "$assume_yes" == "true" ]] && return 0
  read -r -p "${question} [o/N] " answer
  [[ "${answer,,}" == "o" || "${answer,,}" == "oui" ]]
}
