# base-debian

[![Build and Publish](https://github.com/mattcurf/container_ci/actions/workflows/build-publish.yml/badge.svg)](https://github.com/mattcurf/container_ci/actions/workflows/build-publish.yml)

Minimal, hardened Debian Bookworm base container image published to GitHub Container Registry (GHCR). Designed as the foundational `FROM` layer for downstream workloads including Rust, Java, Supabase, and other services. Every published image includes an SBOM, Trivy vulnerability scan, and Cosign signature for supply-chain integrity.

## Quick Start

```bash
docker pull ghcr.io/<org>/base-debian:bookworm
docker run --rm -it ghcr.io/<org>/base-debian:bookworm
```

Replace `<org>` with your GitHub username or organization.

## What's Included

### Installed Packages

| Package | Purpose |
|---------|---------|
| `ca-certificates` | TLS root certificates |
| `curl` | Health checks, downloads |
| `locales` | UTF-8 locale support |
| `tzdata` | Timezone data |
| `libc-bin` | Core C library utilities |

### Hardening Measures

| Measure | Details |
|---------|---------|
| Non-root user | `appuser` (UID 1000) is the default user |
| Working directory | `/app`, owned by `appuser` |
| No SUID/SGID binaries | Stripped during build |
| Healthcheck | `HEALTHCHECK NONE` placeholder for downstream override |
| OCI labels | Full `org.opencontainers.image.*` metadata |
| dpkg excludes | Docs, man pages, and other bloat excluded |

## Tags

| Tag | Description |
|-----|-------------|
| `bookworm` | Latest build of Debian Bookworm base |
| `latest` | Alias for `bookworm` |
| `bookworm-YYYYMMDD` | Date-stamped immutable tag |
| `bookworm-<sha>` | Git SHA pinned tag |

## Downstream Usage

```dockerfile
FROM ghcr.io/<org>/base-debian:bookworm

# Install runtime-specific packages
RUN apt-get update && apt-get install -y --no-install-recommends \
      openjdk-17-jre-headless && \
    rm -rf /var/lib/apt/lists/*

COPY --chown=appuser:appuser ./app /app
USER appuser
CMD ["java", "-jar", "/app/service.jar"]
```

## Verifying the Image

<details>
<summary>Install prerequisites (cosign, jq)</summary>

**macOS:**
```bash
brew install cosign jq
```

**Ubuntu/Debian:**
```bash
sudo apt-get install -y cosign jq
```

**Go (any platform):**
```bash
go install github.com/sigstore/cosign/v2/cmd/cosign@latest
```

</details>

### Cosign Verify

```bash
cosign verify ghcr.io/<org>/base-debian:bookworm \
  --certificate-identity-regexp="https://github.com/<org>/container_ci" \
  --certificate-oidc-issuer="https://token.actions.githubusercontent.com"
```

### SBOM Inspection

<details>
<summary>Install prerequisites (trivy)</summary>

**macOS:**
```bash
brew install trivy
```

**Ubuntu/Debian:**
```bash
sudo apt-get install -y trivy
```

</details>

```bash
# Package names only
trivy image --format spdx-json ghcr.io/<org>/base-debian:bookworm | jq '.packages[].name'

# Package names, versions, and suppliers
trivy image --format spdx-json ghcr.io/<org>/base-debian:bookworm | jq '.packages[] | {name, versionInfo, supplier}'

# Human-readable table with all packages
trivy image --format table --list-all-pkgs ghcr.io/<org>/base-debian:bookworm
```

## Local Development

### Using the build script

```bash
./scripts/build.sh
```

Environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `IMAGE_NAME` | `base-debian` | Image name |
| `TAG` | `bookworm` | Image tag |
| `PLATFORM` | Auto-detected | Target platform |

### Manual build

```bash
docker buildx build \
  --platform linux/amd64 \
  --build-arg BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --build-arg VCS_REF="$(git rev-parse --short HEAD)" \
  --tag base-debian:bookworm \
  --load \
  .
```

## CI/CD Pipeline

### `build-publish.yml`

The main workflow runs on push to `main`, tags matching `v*`, and pull requests. On PRs, it builds the multi-arch image without pushing. On push to main, it runs the full pipeline: build, push, Trivy scan, SBOM generation, Cosign signing, and SARIF upload to GitHub Security.

### `scheduled-rebuild.yml`

A cron-triggered workflow that runs every Monday at 06:00 UTC, calling `build-publish.yml` to ensure the image incorporates the latest Debian security patches.

## Security

See [SECURITY.md](SECURITY.md) for the vulnerability reporting policy and response timelines.

## License

See [LICENSE](LICENSE) for details.
