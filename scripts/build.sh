#!/usr/bin/env bash
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-base-debian}"
TAG="${TAG:-bookworm}"
PLATFORM="${PLATFORM:-linux/$(uname -m | sed 's/x86_64/amd64/' | sed 's/aarch64/arm64/')}"

echo "==> Building ${IMAGE_NAME}:${TAG} for ${PLATFORM}"
docker buildx build \
  --platform "${PLATFORM}" \
  --target runtime \
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
echo "==> Checking for SUID/SGID binaries"
SUID_COUNT=$(docker run --rm "${IMAGE_NAME}:${TAG}" sh -c 'find / -xdev -perm /6000 -type f 2>/dev/null | tee /dev/stderr | wc -l')
if [ "${SUID_COUNT}" -ne 0 ]; then
  echo "FAIL: Found ${SUID_COUNT} SUID/SGID binaries (listed above)"
  exit 1
fi
echo "PASS: No SUID/SGID binaries found"

echo "==> Checking /app ownership"
APP_OWNER=$(docker run --rm "${IMAGE_NAME}:${TAG}" stat -c '%U:%G' /app)
if [ "${APP_OWNER}" != "appuser:appuser" ]; then
  echo "FAIL: /app owned by ${APP_OWNER}, expected appuser:appuser"
  exit 1
fi
echo "PASS: /app owned by appuser:appuser"

echo "==> Checking runtime UID"
RUNTIME_UID=$(docker run --rm "${IMAGE_NAME}:${TAG}" id -u)
if [ "${RUNTIME_UID}" -eq 0 ]; then
  echo "FAIL: Container runs as root (UID 0)"
  exit 1
fi
echo "PASS: Container runs as UID ${RUNTIME_UID}"

echo "==> Checking package allowlist"
docker run --rm "${IMAGE_NAME}:${TAG}" dpkg-query -W -f='${Package}\n' | sort > /tmp/installed-packages.txt
DIFF=$(comm -23 /tmp/installed-packages.txt <(grep -v '^#' packages.allow | grep -v '^$' | sort))
if [ -n "${DIFF}" ]; then
  echo "FAIL: Unapproved packages found:"
  echo "${DIFF}"
  exit 1
fi
echo "PASS: All installed packages are on the allowlist"

echo "==> All tests passed"
