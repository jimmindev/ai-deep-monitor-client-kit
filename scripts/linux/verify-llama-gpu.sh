#!/usr/bin/env sh
set -eu

DEFAULT_IMAGE="ghcr.io/ggml-org/llama.cpp:server-cuda@sha256:8557e3d273aa6010d46f355e826348b691ba3ddffccae8eaf0150596bbc3ec42"
IMAGE="${LLAMA_CPP_IMAGE:-$DEFAULT_IMAGE}"

command -v docker >/dev/null 2>&1 || {
  echo "Docker est requis." >&2
  exit 1
}

docker version >/dev/null

architecture="$(uname -m)"
case "$architecture" in
  x86_64|amd64|aarch64|arm64) ;;
  *)
    echo "Architecture non prise en charge par l'image llama.cpp CUDA: $architecture" >&2
    exit 1
    ;;
esac

if [ -r /proc/device-tree/model ]; then
  device_model="$(tr -d '\000' </proc/device-tree/model)"
  case "$device_model" in
    *Jetson*) echo "Plateforme Jetson detectee: $device_model" ;;
  esac
fi

echo "Verification du GPU depuis le conteneur llama.cpp ($architecture)..."
devices="$(docker run --rm --gpus all "$IMAGE" --list-devices 2>&1)" || {
  printf '%s\n' "$devices" >&2
  echo "Le GPU NVIDIA n'est pas utilisable dans Docker. Verifiez le pilote, le NVIDIA Container Toolkit et, sur Jetson, la compatibilite CUDA/JetPack de LLAMA_CPP_IMAGE." >&2
  exit 1
}
printf '%s\n' "$devices"

printf '%s\n' "$devices" | grep -q "CUDA0:" || {
  echo "llama.cpp ne voit aucun device CUDA. Le demarrage est bloque pour eviter une inference CPU involontaire." >&2
  exit 1
}

echo "GPU CUDA valide pour llama.cpp."
