#!/usr/bin/env bash

set -Eeuo pipefail

export DEFAULT_APP_VERSION="v0.1.15"
export DOCKER_PLATFORM=""
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
OLLAMA_CONFIG_CHANGED=false

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

ensure_ollama_config() {
  local env_file="$1"
  local current_model
  local current_fallback
  local recommended_model="llama3.2:3b"
  local architecture
  local memory_kb

  architecture="$(uname -m 2>/dev/null || true)"
  memory_kb="$(awk '/^MemTotal:/ { print $2; exit }' /proc/meminfo 2>/dev/null || true)"
  if [[ "$architecture" =~ ^(aarch64|arm64)$ ]] &&
     [[ "$memory_kb" =~ ^[0-9]+$ ]] &&
     (( memory_kb < 6291456 )); then
    recommended_model="llama3.2:1b"
  fi

  current_model="$(read_env_value "$env_file" OLLAMA_MODEL)"
  if [[ -z "$current_model" || "$current_model" == "llama3.1" ||
        ( "$recommended_model" == "llama3.2:1b" && "$current_model" == "llama3.2:3b" ) ]]; then
    write_env_value "$env_file" OLLAMA_MODEL "$recommended_model"
    OLLAMA_CONFIG_CHANGED=true
  fi

  current_fallback="$(read_env_value "$env_file" OLLAMA_FALLBACK_MODEL)"
  if [[ -z "$current_fallback" || "$current_fallback" == "llama3.1" ||
        "$current_fallback" == "llama3.2:3b" ]]; then
    write_env_value "$env_file" OLLAMA_FALLBACK_MODEL "llama3.2:1b"
    OLLAMA_CONFIG_CHANGED=true
  fi
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
  compose_exec -p "$project" -f "$compose_file" --env-file "$env_file" ps || true
  warn "Derniers journaux utiles:"
  compose_exec -p "$project" -f "$compose_file" --env-file "$env_file" \
    logs --tail=120 mysql sandbox ollama ollama-models api collector || true
}

project_name_from_dir() {
  basename "$1" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9_-'
}

existing_data_volumes() {
  local project="$1"
  local expected
  expected="${project}_client_(mysql_data|api_data|uploaded_mibs|generated_backups|ollama_data|sandbox_jobs)"
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

ghcr_tags() {
  local owner="$1"
  local image="$2"
  local user="$3"
  local token="$4"
  local bearer
  bearer="$(ghcr_bearer_token "$owner" "$image" "$user" "$token")"
  [[ -n "$bearer" ]] || return 1
  curl -fsS -H "Authorization: Bearer ${bearer}" \
    "https://ghcr.io/v2/${owner}/${image}/tags/list" |
    grep -Eo '"v[0-9]+\.[0-9]+\.[0-9]+"' |
    tr -d '"' |
    sort -V -u
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
