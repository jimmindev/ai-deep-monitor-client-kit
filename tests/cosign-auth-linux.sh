#!/usr/bin/env bash
set -Eeuo pipefail
KIT_DIR="${1:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"' EXIT
mkdir -p "$TEST_DIR/bin" "$TEST_DIR/kit"
cp "$KIT_DIR/scripts/linux/verify-images.sh" "$KIT_DIR/scripts/linux/signing-policy.json" "$TEST_DIR/kit/"
export EXPECTED_AUTH_ROOT="$TEST_DIR/kit" EXPECTED_UID="$(id -u):$(id -g)"
export TMPDIR="$TEST_DIR/invisible-private-tmp" GHCR_USER=test-reader GHCR_TOKEN=test-token
export PATH="$TEST_DIR/bin:$PATH"
cat > "$TEST_DIR/bin/docker" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
if [[ "$1" == --config ]]; then
  [[ "$2" == "$EXPECTED_AUTH_ROOT"/.cosign-auth.* ]]
  [[ "$(stat -c %a "$2")" == 700 ]]
  [[ "$(cat)" == test-token ]]
  printf '{"auths":{}}' > "$2/config.json"
elif [[ "$1" == image ]]; then
  printf '%s@sha256:%064d\n' "${3%:*}" 1
elif [[ "$1" == run ]]; then
  [[ "$3" == --user && "$4" == "$EXPECTED_UID" ]]
  [[ "$7" == --tmpfs && "$9" == --env && "${11}" == --mount ]]
  source_dir="${12#type=bind,source=}"
  source_dir="${source_dir%,target=/auth,readonly}"
  [[ -r "$source_dir/config.json" ]]
  exit "${VERIFY_TEST_EXIT:-0}"
else
  exit 98
fi
EOF
chmod +x "$TEST_DIR/bin/docker"
sh "$TEST_DIR/kit/verify-images.sh" jimmindev v0.1.53 >/dev/null
! compgen -G "$TEST_DIR/kit/.cosign-auth.*" >/dev/null
export VERIFY_TEST_EXIT=17
if sh "$TEST_DIR/kit/verify-images.sh" jimmindev v0.1.53 >/dev/null; then
  echo 'Signature failure was ignored' >&2
  exit 1
else
  [[ "$?" == 17 ]]
fi
! compgen -G "$TEST_DIR/kit/.cosign-auth.*" >/dev/null
echo COSIGN_AUTH_OK
