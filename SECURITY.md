# Security Policy

## Supported Versions

| Version | Supported |
|---------|-----------|
| `bookworm` (latest) | ✅ Yes |

## Reporting a Vulnerability

**Please do not report security vulnerabilities through public GitHub issues.**

Instead, please use [GitHub Security Advisories](https://github.com/mattcurf/container_ci/security/advisories/new) to report vulnerabilities privately. This allows us to assess and address the issue before public disclosure.

### What to include

- Description of the vulnerability
- Steps to reproduce
- Affected versions / tags
- Potential impact

## Response Timeline

| Action | SLA |
|--------|-----|
| Acknowledge report | Within 48 hours |
| Initial assessment | Within 72 hours |
| Patch for critical severity | Within 7 days |
| Patch for high severity | Within 14 days |

## Scope

This security policy covers:

- The `base-debian` container image
- The CI/CD pipeline (`build-publish.yml`, `scheduled-rebuild.yml`)
- Build scripts and configuration in this repository

**Out of scope:**

- Downstream images built `FROM` this base image
- Third-party dependencies introduced by downstream consumers

## Automated Security Measures

This project employs the following automated security practices:

- **Weekly rebuilds** to incorporate the latest Debian security patches
- **Trivy vulnerability scanning** on every build, failing on CRITICAL and HIGH severity findings
- **Cosign image signing** for supply-chain integrity verification
- **SBOM generation** (SPDX format) attached to every published image
- **SLSA provenance** attestation via BuildKit
