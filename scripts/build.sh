#!/usr/bin/env bash
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-base-debian}"
TAG="${TAG:-bookworm}"
PLATFORM="${PLATFORM:-linux/$(uname -m | sed 's/x86_64/amd64/' | sed 's/aarch64/arm64/')}"

echo "==> Building ${IMAGE_NAME}:${TAG} for ${PLATFORM}"
docker buildx build \
  --platform "${PLATFORM}" \
  --build-arg BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --build-arg VCS_REF="$(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')" \
  --tag "${IMAGE_NAME}:${TAG}" \
  --load \
  .

echo "==> Image size"
docker images "${IMAGE_NAME}:${TAG}" --format "{{.Repository}}:{{.Tag}} {{.Size}}"

echo "==> Running smoke tests"
docker run --rm "${IMAGE_NAME}:${TAG}" id
docker run --rm "${IMAGE_NAME}:${TAG}" locale
docker run --rm "${IMAGE_NAME}:${TAG}" curl --version > /dev/null
docker run --rm "${IMAGE_NAME}:${TAG}" sh -c 'find / -xdev -perm /6000 -type f 2>/dev/null | wc -l'

echo "==> All tests passed"
