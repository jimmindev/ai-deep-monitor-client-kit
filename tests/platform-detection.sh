#!/usr/bin/env bash

set -Eeuo pipefail

KIT_DIR="${1:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=../client-common.sh
source "${KIT_DIR}/client-common.sh"

[[ "$(resolve_docker_platform linux amd64)" == "linux/amd64" ]]
[[ "$(resolve_docker_platform linux x86_64)" == "linux/amd64" ]]
[[ "$(resolve_docker_platform linux arm64)" == "linux/arm64" ]]
[[ "$(resolve_docker_platform linux aarch64)" == "linux/arm64" ]]

if resolve_docker_platform windows amd64 >/dev/null 2>&1; then
  printf 'WINDOWS_CONTAINER_MODE_SHOULD_FAIL\n' >&2
  exit 1
fi

if resolve_docker_platform linux armv7 >/dev/null 2>&1; then
  printf 'UNSUPPORTED_ARCH_SHOULD_FAIL\n' >&2
  exit 1
fi

printf 'PLATFORM_DETECTION_OK\n'
