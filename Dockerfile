# Pinned: debian:bookworm-slim as of 2026-03-14
FROM debian:bookworm-slim@sha256:74d56e3931e0d5a1dd51f8c8a2466d21de84a271cd3b5a733b803aa91abf4421 AS builder

ARG BUILD_DATE
ARG VCS_REF

LABEL org.opencontainers.image.source="https://github.com/mattcurf/container_ci" \
      org.opencontainers.image.description="Minimal hardened Debian bookworm base image" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.created="${BUILD_DATE}"

COPY rootfs/ /

RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      locales \
      tzdata \
      libc-bin && \
    sed -i 's/^# *en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen && \
    locale-gen && \
    rm -rf /var/lib/apt/lists/*

COPY scripts/strip-suid.sh /tmp/strip-suid.sh
RUN sh /tmp/strip-suid.sh && rm /tmp/strip-suid.sh

RUN groupadd -r appuser && useradd -r -g appuser -u 1000 -m -d /app -s /bin/sh appuser

# --- Debug variant: full tooling for troubleshooting ---
FROM builder AS debug

ENV LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
ENV TZ=Etc/UTC

WORKDIR /app
HEALTHCHECK NONE
USER appuser
CMD ["/bin/bash"]

# --- Runtime variant: minimal attack surface (default) ---
FROM debian:bookworm-slim@sha256:74d56e3931e0d5a1dd51f8c8a2466d21de84a271cd3b5a733b803aa91abf4421 AS runtime

COPY --from=builder /etc/passwd /etc/passwd
COPY --from=builder /etc/group /etc/group
COPY --from=builder /etc/shadow /etc/shadow
COPY --from=builder /etc/ssl/certs /etc/ssl/certs
COPY --from=builder /usr/share/zoneinfo /usr/share/zoneinfo
COPY --from=builder /usr/lib/locale /usr/lib/locale
COPY --from=builder /app /app

ARG BUILD_DATE
ARG VCS_REF

LABEL org.opencontainers.image.source="https://github.com/mattcurf/container_ci" \
      org.opencontainers.image.description="Minimal hardened Debian bookworm base image (runtime)" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.created="${BUILD_DATE}"

ENV LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
ENV TZ=Etc/UTC

WORKDIR /app
HEALTHCHECK NONE
USER appuser
CMD ["/bin/sh"]
