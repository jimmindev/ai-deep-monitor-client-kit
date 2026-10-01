#!/usr/bin/env sh
set -eu

TRUSTED_OWNER="jimmindev"
TRUSTED_REPOSITORY="ai-deep-monitor"
ISSUER="https://token.actions.githubusercontent.com"
COSIGN_IMAGE="ghcr.io/sigstore/cosign/cosign:v3.1.3@sha256:9e5c2f2edc34351160407ca3416c61855bdf9403c3c5936e0f0be7fc261611b8"
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"
POLICY_FILE="$SCRIPT_DIR/signing-policy.json"

OWNER="${1:-$TRUSTED_OWNER}"
APP_VERSION="${2:-}"
GHCR_USER="${GHCR_USER:-${UPDATE_CHECK_USER:-}}"
GHCR_TOKEN="${GHCR_TOKEN:-${UPDATE_CHECK_TOKEN:-}}"

if [ "$OWNER" != "$TRUSTED_OWNER" ]; then
  echo "Proprietaire GHCR non approuve: $OWNER. Seul $TRUSTED_OWNER est autorise." >&2
  exit 1
fi
if ! printf '%s' "$APP_VERSION" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "Version invalide pour la verification de signature: $APP_VERSION" >&2
  exit 1
fi
if [ -z "$GHCR_USER" ] || [ -z "$GHCR_TOKEN" ]; then
  echo "GHCR_USER et GHCR_TOKEN sont requis pour verifier les signatures privees." >&2
  exit 1
fi
command -v docker >/dev/null 2>&1 || {
  echo "Docker est requis pour verifier les signatures des images." >&2
  exit 1
}

command -v python3 >/dev/null 2>&1 || {
  echo "Python 3 est requis pour lire la politique de signature." >&2
  exit 1
}
[ -f "$POLICY_FILE" ] || {
  echo "Politique de signature absente. La mise a jour est bloquee." >&2
  exit 1
}
policy_values="$(python3 - "$POLICY_FILE" <<'PY'
import json
import sys
policy = json.load(open(sys.argv[1], encoding="utf-8"))
for key in ("local_from_version", "identity", "issuer"):
    value = str(policy.get(key) or "")
    if "\n" in value or "\r" in value:
        raise ValueError("Invalid signing policy value")
    print(value)
PY
)"
local_from_version="$(printf '%s\n' "$policy_values" | sed -n '1p')"
local_identity="$(printf '%s\n' "$policy_values" | sed -n '2p')"
local_issuer="$(printf '%s\n' "$policy_values" | sed -n '3p')"
if ! printf '%s' "$local_from_version" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "Version de transition Cosign invalide." >&2
  exit 1
fi
version_number() {
  printf '%s\n' "$1" | awk -F '[v.]' '{printf "%d%06d%06d", $2, $3, $4}'
}
local_signer_required=false
if [ "$(version_number "$APP_VERSION")" -ge "$(version_number "$local_from_version")" ]; then
  local_signer_required=true
  if [ -z "$local_identity" ] || [ "$local_identity" = "PENDING_COSIGN_PILOT" ] || [ -z "$local_issuer" ]; then
    echo "Identite Cosign locale non approuvee. La mise a jour est bloquee." >&2
    exit 1
  fi
fi

# The host agent uses systemd PrivateTmp. Docker's daemon cannot see its /tmp.
# Keep credentials in the shared installation, private to the invoking user.
umask 077
docker_config_dir="$(mktemp -d "$SCRIPT_DIR/.cosign-auth.XXXXXX")"
cosign_user="$(id -u):$(id -g)"
cleanup() {
  rm -rf -- "$docker_config_dir"
}
trap cleanup EXIT HUP INT TERM

printf '%s' "$GHCR_TOKEN" | docker --config "$docker_config_dir" login ghcr.io --username "$GHCR_USER" --password-stdin >/dev/null

escaped_version="$(printf '%s' "$APP_VERSION" | sed 's/\./\\./g')"
identity_regexp="^https://github\\.com/$TRUSTED_OWNER/$TRUSTED_REPOSITORY/\\.github/workflows/docker-images\\.yml@(refs/heads/main|refs/tags/$escaped_version)$"

for image_name in ai-deep-monitor-api ai-deep-monitor-frontend; do
  repository="ghcr.io/$TRUSTED_OWNER/$image_name"
  tagged_reference="$repository:$APP_VERSION"
  digest_reference="$(
    docker image inspect "$tagged_reference" --format '{{range .RepoDigests}}{{println .}}{{end}}' |
      grep -F -m 1 "$repository@sha256:" || true
  )"
  if [ -z "$digest_reference" ]; then
    echo "Digest immuable introuvable pour $tagged_reference. La mise a jour est bloquee." >&2
    exit 1
  fi
  echo "Verification de la signature: $digest_reference"
  if [ "$local_signer_required" = true ]; then
    docker run --rm \
      --user "$cosign_user" \
      --env HOME=/tmp \
      --tmpfs /tmp:rw,nosuid,nodev,size=32m \
      --env DOCKER_CONFIG=/auth \
      --mount "type=bind,source=$docker_config_dir,target=/auth,readonly" \
      "$COSIGN_IMAGE" verify \
      --certificate-identity "$local_identity" \
      --certificate-oidc-issuer "$local_issuer" \
      "$digest_reference"
  else
    docker run --rm \
      --user "$cosign_user" \
      --env HOME=/tmp \
      --tmpfs /tmp:rw,nosuid,nodev,size=32m \
      --env DOCKER_CONFIG=/auth \
      --mount "type=bind,source=$docker_config_dir,target=/auth,readonly" \
      "$COSIGN_IMAGE" verify \
      --certificate-identity-regexp "$identity_regexp" \
      --certificate-oidc-issuer "$ISSUER" \
      "$digest_reference"
  fi
done

echo "Signatures Cosign valides pour les images $APP_VERSION."
