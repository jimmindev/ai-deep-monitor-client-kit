#!/usr/bin/env bash

set -Eeuo pipefail

KIT_DIR="${1:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=../scripts/linux/client-common.sh
source "${KIT_DIR}/scripts/linux/client-common.sh"

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

[[ "$(llama_cuda_base_images 12.6)" == 'nvidia/cuda:12.6.3-devel-ubuntu24.04|nvidia/cuda:12.6.3-runtime-ubuntu24.04' ]]
[[ "$(llama_cuda_base_images 11.4)" == 'nvidia/cuda:11.4.3-devel-ubuntu20.04|nvidia/cuda:11.4.3-runtime-ubuntu20.04' ]]
if llama_cuda_base_images 10.2 >/dev/null 2>&1; then
  printf 'UNSUPPORTED_CUDA_SHOULD_FAIL\n' >&2
  exit 1
fi

printf 'PLATFORM_DETECTION_OK\n'
