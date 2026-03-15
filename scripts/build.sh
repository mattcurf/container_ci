#!/usr/bin/env bash
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-base-debian}"
TAG="${TAG:-runtime-bookworm}"
DEV_TAG="${DEV_TAG:-dev-bookworm}"
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

echo "==> Running runtime smoke tests"
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

echo "==> Checking runtime command surface"
for cmd in apt-get dpkg-query bash; do
  if docker run --rm "${IMAGE_NAME}:${TAG}" sh -c "command -v ${cmd} >/dev/null 2>&1"; then
    echo "FAIL: Runtime image exposes ${cmd}"
    exit 1
  fi
done
docker run --rm "${IMAGE_NAME}:${TAG}" sh -c 'command -v sh >/dev/null 2>&1'
echo "PASS: Runtime image exposes only the expected shell surface"

echo "==> Checking package allowlist"
docker run --rm "${IMAGE_NAME}:${TAG}" cat /app/.package-manifest > /tmp/installed-packages.txt
APPROVED_RUNTIME=$(grep -v '^#' packages.allow | grep -v '^$' | sort)
RUNTIME_EXTRA=$(comm -23 /tmp/installed-packages.txt <(printf '%s\n' "${APPROVED_RUNTIME}"))
RUNTIME_MISSING=$(comm -13 /tmp/installed-packages.txt <(printf '%s\n' "${APPROVED_RUNTIME}"))
if [ -n "${RUNTIME_EXTRA}" ]; then
  echo "FAIL: Unapproved packages found:"
  echo "${RUNTIME_EXTRA}"
  exit 1
fi
if [ -n "${RUNTIME_MISSING}" ]; then
  echo "FAIL: Approved runtime packages missing from manifest:"
  echo "${RUNTIME_MISSING}"
  exit 1
fi
echo "PASS: Runtime package manifest matches the allowlist exactly"

echo "==> All runtime tests passed"

echo "==> Building ${IMAGE_NAME}:${DEV_TAG} for ${PLATFORM}"
docker buildx build \
  --platform "${PLATFORM}" \
  --target dev \
  --build-arg BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --build-arg VCS_REF="$(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')" \
  --tag "${IMAGE_NAME}:${DEV_TAG}" \
  --load \
  .

echo "==> Image size (dev)"
docker images "${IMAGE_NAME}:${DEV_TAG}" --format "{{.Repository}}:{{.Tag}} {{.Size}}"

echo "==> Running dev smoke tests"
docker run --rm "${IMAGE_NAME}:${DEV_TAG}" id
docker run --rm "${IMAGE_NAME}:${DEV_TAG}" bash --version
docker run --rm "${IMAGE_NAME}:${DEV_TAG}" curl --version
docker run --rm "${IMAGE_NAME}:${DEV_TAG}" apt-get --version

echo "==> Checking dev UID"
DEV_UID=$(docker run --rm "${IMAGE_NAME}:${DEV_TAG}" id -u)
if [ "${DEV_UID}" -eq 0 ]; then
  echo "FAIL: Dev container runs as root (UID 0)"
  exit 1
fi
echo "PASS: Dev container runs as UID ${DEV_UID}"

echo "==> Checking dev package allowlist"
docker run --rm "${IMAGE_NAME}:${DEV_TAG}" dpkg-query -W -f='${Package}\n' | sort > /tmp/installed-packages-dev.txt
APPROVED_DEV=$(grep -v '^#' packages.allow.dev | grep -v '^$' | sort)
DEV_EXTRA=$(comm -23 /tmp/installed-packages-dev.txt <(printf '%s\n' "${APPROVED_DEV}"))
DEV_MISSING=$(comm -13 /tmp/installed-packages-dev.txt <(printf '%s\n' "${APPROVED_DEV}"))
if [ -n "${DEV_EXTRA}" ]; then
  echo "FAIL: Unapproved dev packages found:"
  echo "${DEV_EXTRA}"
  exit 1
fi
if [ -n "${DEV_MISSING}" ]; then
  echo "FAIL: Approved dev packages missing from install set:"
  echo "${DEV_MISSING}"
  exit 1
fi
echo "PASS: Dev package set matches the allowlist exactly"

echo "==> All tests passed"
