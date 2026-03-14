# base-debian

[![Build and Publish](https://github.com/mattcurf/container_ci/actions/workflows/build-publish.yml/badge.svg)](https://github.com/mattcurf/container_ci/actions/workflows/build-publish.yml)

Minimal, hardened Debian Bookworm base container image published to GitHub Container Registry (GHCR). Designed as the foundational `FROM` layer for downstream workloads including Rust, Java, Supabase, and other services. Every published image includes an SBOM, Trivy vulnerability scan, and Cosign signature for supply-chain integrity.

## Quick Start

```bash
docker pull ghcr.io/<org>/base-debian:runtime-bookworm
docker run --rm -it ghcr.io/<org>/base-debian:runtime-bookworm
```

Replace `<org>` with your GitHub username or organization.

## Image Variants

| Variant | Tag suffix | Contents | Use case |
|---------|-----------|----------|----------|
| Runtime | `runtime-bookworm` | Curated Debian runtime files: `/bin/sh`, core runtime utilities, CA certs, timezone, locale, required shared libraries | Production workloads (final stage only) |
| Dev     | `dev-bookworm` | Adds bash, curl, apt-get | Build stages, troubleshooting, development |

## What's Included

### Runtime variant

The runtime image is assembled from a curated Debian runtime filesystem rather than a full `debian:bookworm-slim` rootfs. It includes:

- `/bin/sh` for container init
- non-root user metadata for `appuser`
- core runtime utilities used by the local verification flow
- CA certificates, timezone data, locale data, and required shared libraries
- no `apt-get`, no `dpkg-query`, and no `bash`

The exact audited package contract is embedded in `/app/.package-manifest` and published as a CI artifact on every build.

### Dev variant (adds)

| Package | Purpose |
|---------|---------|
| `bash` | Interactive shell |
| `curl` | Health checks, downloads |

### Hardening Measures

| Measure | Details |
|---------|---------|
| Non-root user | `appuser` (UID 1000) is the default user; enforced by build-time assertion |
| Working directory | `/app`, owned by `appuser`; ownership verified at build time |
| No SUID/SGID binaries | Stripped during build; enforced by fail-closed smoke test |
| Pinned CI actions | All GitHub Actions pinned to immutable commit SHAs |
| Pinned base image | `debian:bookworm-slim` pinned by digest for reproducibility |
| Package allowlist | Installed packages gated against a reviewed baseline |
| Digest-based verification | Scans, signatures, SBOMs, and attestations tied to the exact built digest |
| Deployment guidance | Docker, Compose, and Kubernetes hardening examples provided |
| Healthcheck | `HEALTHCHECK NONE` placeholder for downstream override |
| OCI labels | Full `org.opencontainers.image.*` metadata |
| dpkg excludes | Docs, man pages, and other bloat excluded |

## Tags

| Tag | Description |
|-----|-------------|
| `runtime-bookworm` | Latest build of runtime variant |
| `dev-bookworm` | Latest build of dev variant |
| `runtime-bookworm-YYYYMMDD` | Date-stamped immutable runtime tag |
| `dev-bookworm-YYYYMMDD` | Date-stamped immutable dev tag |
| `runtime-bookworm-<sha>` | Git SHA pinned runtime tag |
| `dev-bookworm-<sha>` | Git SHA pinned dev tag |

## Downstream Usage

```dockerfile
# Build stage
FROM ghcr.io/<org>/base-debian:dev-bookworm AS build

RUN apt-get update && apt-get install -y --no-install-recommends \
      openjdk-17-jdk-headless maven && \
    rm -rf /var/lib/apt/lists/*

COPY . /app
RUN cd /app && mvn package

# Runtime stage
FROM ghcr.io/<org>/base-debian:runtime-bookworm

COPY --from=build --chown=appuser:appuser /app/target/service.jar /app/service.jar
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
cosign verify ghcr.io/<org>/base-debian:runtime-bookworm \
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
trivy image --format spdx-json ghcr.io/<org>/base-debian:runtime-bookworm | jq '.packages[].name'

# Package names, versions, and suppliers
trivy image --format spdx-json ghcr.io/<org>/base-debian:runtime-bookworm | jq '.packages[] | {name, versionInfo, supplier}'

# Human-readable table with all packages
trivy image --format table --list-all-pkgs ghcr.io/<org>/base-debian:runtime-bookworm
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
| `TAG` | `runtime-bookworm` | Runtime image tag |
| `DEV_TAG` | `dev-bookworm` | Dev image tag |
| `PLATFORM` | Auto-detected | Target platform |

### Manual build

```bash
# Runtime variant
docker buildx build \
  --platform linux/amd64 \
  --target runtime \
  --build-arg BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --build-arg VCS_REF="$(git rev-parse --short HEAD)" \
  --tag base-debian:runtime-bookworm \
  --load \
  .

# Dev variant
docker buildx build \
  --platform linux/amd64 \
  --target dev \
  --build-arg BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --build-arg VCS_REF="$(git rev-parse --short HEAD)" \
  --tag base-debian:dev-bookworm \
  --load \
  .
```

## CI/CD Pipeline

### `build-publish.yml`

The main workflow runs on push to `main`, tags matching `v*`, and pull requests. On PRs, it builds the multi-arch image without pushing. On push to main, it runs the full pipeline: build, push, Trivy scan **by digest**, SBOM generation, Cosign signing, and SARIF upload to GitHub Security. All post-build verification steps operate on the immutable image digest, not a mutable tag. Each build records the pinned base image digest and full package manifest as downloadable artifacts for audit and traceability. Both `runtime-bookworm` and `dev-bookworm` variants are built, scanned, signed, and attested independently.

### `nightly-scan.yml`

Runs Trivy against the published image every night at 02:00 UTC. The workflow resolves the current image digest before scanning, ensuring results are tied to an immutable artifact. Uploads SARIF results to the GitHub Security tab and fails if CRITICAL or HIGH severity CVEs with available fixes are found.

### `scheduled-rebuild.yml`

Manual-only (`workflow_dispatch`). Trigger from the Actions tab to rebuild and republish the image when a nightly scan finds CVEs that require a rebuild to resolve.

## Security

See [SECURITY.md](SECURITY.md) for the vulnerability reporting policy and response timelines.

## Deployment Hardening

See [DEPLOYMENT.md](DEPLOYMENT.md) for required runtime flags, security profiles, network policy, and secrets handling guidance when deploying images based on this base.

## Image Strategy

See [development.md](development.md) for the canonical policy on the runtime/dev image split, tagging policy, and downstream usage contract.

## License

The repository source and packaging logic are licensed under [Apache 2.0](LICENSE).

Published images include Debian packages and other third-party components under their own upstream licenses. Use the published SBOM and package metadata for component-level licensing and attribution.
