# Deployment Hardening Guide

This document defines the runtime security contract for containers built from `base-debian`. A secure base image alone is not sufficient — downstream consumers must enforce runtime policy.

> **Note:** Deployment examples use the `runtime-bookworm` image exclusively. The `dev-bookworm` image is intended for build and debug stages only and must not be deployed to production.

## Runtime Requirements

All containers derived from this base image **must** be launched with the following flags:

| Flag | Purpose |
|------|---------|
| `--read-only` | Mount the root filesystem as read-only to prevent runtime tampering |
| `--security-opt=no-new-privileges` | Prevent child processes from gaining additional privileges via `setuid`, `setgid`, or filesystem capabilities |
| `--cap-drop=ALL` | Drop all Linux capabilities; re-add only those explicitly required |
| `--tmpfs /tmp:rw,noexec,nosuid,size=64m` | Provide a writable `/tmp` without execute or setuid permissions |

If your application requires writable storage, mount explicit volumes only where necessary (e.g., `/app/data`). Never run with a writable root filesystem in production.

## Recommended Security Profiles

### Seccomp

Use the Docker default seccomp profile, which blocks approximately 44 of 300+ syscalls. If your workload permits, apply a custom profile that further restricts allowed syscalls:

```bash
docker run --rm \
  --security-opt seccomp=/path/to/custom-seccomp.json \
  ghcr.io/<org>/base-debian:runtime-bookworm
```

### AppArmor / SELinux

- **AppArmor** (Ubuntu/Debian hosts): The default `docker-default` AppArmor profile is applied automatically. For additional restrictions, load and assign a custom profile.
- **SELinux** (RHEL/Fedora hosts): Run containers with `--security-opt label=type:container_runtime_t` or an equivalent confined type.

## Network Policy

Apply a default-deny egress policy and explicitly allow only required destinations:

- DNS resolution (UDP/TCP port 53) to cluster DNS
- Application-specific endpoints (e.g., database hosts, API gateways)
- Package repositories only during build, never at runtime

Block all other outbound traffic. In Kubernetes, use `NetworkPolicy` resources (see examples below). In Docker, use `--network=none` for fully isolated workloads or user-defined bridge networks with iptables rules.

## Secrets Handling

- **No secrets baked into images**: Never use `ENV`, `ARG`, or `COPY` to embed credentials, API keys, or certificates into the image.
- **Short-lived workload identity**: Prefer OIDC-based workload identity (e.g., AWS IRSA, GCP Workload Identity, Azure Managed Identity) over static credentials.
- **Runtime injection**: Mount secrets via tmpfs-backed volumes, Kubernetes Secrets (with encryption at rest), or a secrets manager sidecar.
- **File permissions**: When mounting secret files, ensure they are owned by `appuser` (UID 1000) and have mode `0400` (read-only by owner).

## Deployment Examples

### Docker Run

```bash
# Run with all recommended hardening flags
docker run --rm \
  --read-only \                          # Prevent runtime filesystem modification
  --security-opt=no-new-privileges \     # Block privilege escalation via setuid/setgid
  --cap-drop=ALL \                       # Drop all Linux capabilities
  --tmpfs /tmp:rw,noexec,nosuid,size=64m \  # Writable /tmp without execute permissions
  ghcr.io/<org>/base-debian:runtime-bookworm \
  /app/my-service
```

### Docker Compose

```yaml
services:
  app:
    image: ghcr.io/<org>/base-debian:runtime-bookworm
    read_only: true               # Read-only root filesystem
    security_opt:
      - no-new-privileges         # Prevent privilege escalation
    cap_drop:
      - ALL                       # Drop all capabilities
    tmpfs:
      - /tmp:rw,noexec,nosuid,size=64m  # Writable tmpfs for temporary files
```

### Kubernetes Pod SecurityContext

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: app
spec:
  containers:
    - name: app
      image: ghcr.io/<org>/base-debian:runtime-bookworm
      securityContext:
        runAsNonRoot: true              # Require non-root user
        runAsUser: 1000                 # Run as appuser (UID 1000)
        readOnlyRootFilesystem: true    # Immutable root filesystem
        allowPrivilegeEscalation: false # No privilege escalation
        capabilities:
          drop: ["ALL"]                 # Drop all capabilities
      volumeMounts:
        - name: tmp
          mountPath: /tmp
  volumes:
    - name: tmp
      emptyDir:
        medium: Memory
        sizeLimit: 64Mi
```

### Kubernetes NetworkPolicy (Default Deny Egress)

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-egress
spec:
  podSelector: {}          # Apply to all pods in the namespace
  policyTypes:
    - Egress
  egress:
    - to: []               # Deny all egress by default
      ports:
        - protocol: UDP
          port: 53          # Allow DNS resolution only
        - protocol: TCP
          port: 53
```
