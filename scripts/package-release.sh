#!/usr/bin/env bash

set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPOSITORY_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd -P)"
OUTPUT_DIR="${1:-${REPOSITORY_ROOT}/artifacts}"
ROOT_NAME="ai-deep-monitor-client-kit"
ZIP_NAME="${ROOT_NAME}.zip"
TAR_NAME="${ROOT_NAME}.tar.gz"
CHECKSUM_NAME="${ROOT_NAME}-SHA256.txt"

for command_name in zip tar sha256sum; do
  command -v "$command_name" >/dev/null 2>&1 || {
    printf 'Commande requise introuvable: %s\n' "$command_name" >&2
    exit 1
  }
done

version="$(tr -d '\r\n' <"${REPOSITORY_ROOT}/VERSION")"
[[ "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
  printf 'Version invalide: %s\n' "$version" >&2
  exit 1
}

mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd -P)"
temporary_dir="$(mktemp -d)"
trap 'rm -rf -- "$temporary_dir"' EXIT
package_root="${temporary_dir}/${ROOT_NAME}"
mkdir -p "$package_root"

for directory in deploy docs host_terminal_agent scripts; do
  cp -a "${REPOSITORY_ROOT}/${directory}" "$package_root/"
done
for file in \
  AI-Deep-Monitor.cmd \
  ai-deep-monitor.ps1 \
  ai-deep-monitor.sh \
  CHANGELOG.md \
  README.md \
  VERSION; do
  cp -a "${REPOSITORY_ROOT}/${file}" "$package_root/"
done

find "$package_root" -type f -name '*.sh' -exec chmod 0755 {} +
find "$package_root" -type f ! -name '*.sh' -exec chmod 0644 {} +

rm -f -- \
  "${OUTPUT_DIR}/${ZIP_NAME}" \
  "${OUTPUT_DIR}/${TAR_NAME}" \
  "${OUTPUT_DIR}/${CHECKSUM_NAME}"
(
  cd "$temporary_dir"
  zip -q -r "${OUTPUT_DIR}/${ZIP_NAME}" "$ROOT_NAME"
  tar -czf "${OUTPUT_DIR}/${TAR_NAME}" "$ROOT_NAME"
)
(
  cd "$OUTPUT_DIR"
  sha256sum "$ZIP_NAME" "$TAR_NAME" >"$CHECKSUM_NAME"
)

printf 'Client Kit %s construit dans %s\n' "$version" "$OUTPUT_DIR"
printf 'Les deux archives contiennent uniquement le dossier racine %s/.\n' "$ROOT_NAME"
