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

cpu_image="$LLAMA_CPP_DEFAULT_CPU_IMAGE"
cuda_image="$LLAMA_CPP_DEFAULT_CUDA_IMAGE"
[[ "$(llama_gpu_probe_candidate nvidia "$cpu_image")" == "$cuda_image" ]]
[[ "$(llama_gpu_probe_candidate nvidia custom/cuda:test)" == 'custom/cuda:test' ]]
[[ "$(llama_gpu_probe_candidate jetson custom/jetpack:test)" == 'custom/jetpack:test' ]]
if llama_gpu_probe_candidate jetson "$cpu_image" >/dev/null 2>&1; then
  printf 'JETSON_CPU_IMAGE_SHOULD_NOT_BE_PROBED\n' >&2
  exit 1
fi
if llama_gpu_probe_candidate jetson "$cuda_image" >/dev/null 2>&1; then
  printf 'JETSON_GENERIC_CUDA_SHOULD_NOT_BE_PROBED\n' >&2
  exit 1
fi
if llama_gpu_probe_candidate jetson 'ghcr.io/ggml-org/llama.cpp:server-cuda@sha256:another' >/dev/null 2>&1; then
  printf 'JETSON_OTHER_GENERIC_CUDA_SHOULD_NOT_BE_PROBED\n' >&2
  exit 1
fi

llama_is_jetson() { return 0; }
docker_exec() { printf '{"nvidia":{},"runc":{}}\n'; }
llama_jetson_runtime_available
docker_exec() { printf '{"runc":{}}\n'; }
if llama_jetson_runtime_available; then
  printf 'JETSON_MISSING_NVIDIA_RUNTIME_SHOULD_FAIL\n' >&2
  exit 1
fi

grep -Fq -- '-DCMAKE_EXE_LINKER_FLAGS="-Wl,--allow-shlib-undefined"' \
  "${KIT_DIR}/deploy/Dockerfile.llama-cuda"
grep -Fq -- 'ARG BUILD_JOBS=4' "${KIT_DIR}/deploy/Dockerfile.llama-cuda"
grep -Fq -- '-j"${BUILD_JOBS}"' "${KIT_DIR}/deploy/Dockerfile.llama-cuda"

printf 'PLATFORM_DETECTION_OK\n'
