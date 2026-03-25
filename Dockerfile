# Pinned: debian:bookworm-slim as of 2026-03-14
FROM debian:bookworm-slim@sha256:74d56e3931e0d5a1dd51f8c8a2466d21de84a271cd3b5a733b803aa91abf4421 AS builder

ARG BUILD_DATE
ARG VCS_REF

LABEL org.opencontainers.image.source="https://github.com/mattcurf/container_ci" \
      org.opencontainers.image.description="Minimal hardened Debian bookworm base image" \
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

# --- Dev variant: build/debug image with full tooling ---
FROM builder AS dev

LABEL org.opencontainers.image.description="Minimal hardened Debian bookworm base image (dev)"

ENV LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
ENV TZ=Etc/UTC

WORKDIR /app
HEALTHCHECK NONE
USER appuser
CMD ["/bin/bash"]

# --- Runtime prep: install and assemble the curated Debian runtime filesystem ---
FROM debian:bookworm-slim@sha256:74d56e3931e0d5a1dd51f8c8a2466d21de84a271cd3b5a733b803aa91abf4421 AS runtime-prep

COPY rootfs/ /
COPY packages.allow /tmp/packages.allow

RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y --no-install-recommends \
      ca-certificates \
      locales \
      tzdata \
      libc-bin && \
    sed -i 's/^# *en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen && \
    locale-gen && \
    rm -rf /var/lib/apt/lists/*

COPY scripts/strip-suid.sh /tmp/strip-suid.sh
RUN sh /tmp/strip-suid.sh && rm /tmp/strip-suid.sh

RUN groupadd -r appuser && useradd -r -g appuser -u 1000 -m -d /app -s /bin/sh appuser && \
    chown appuser:appuser /app

RUN dpkg-query -W -f='${Package}\n' | sort > /tmp/runtime-packages.installed && \
    grep -v '^#' /tmp/packages.allow | grep -v '^$' | sort > /tmp/runtime-packages.requested && \
    comm -23 /tmp/runtime-packages.installed /tmp/runtime-packages.requested > /tmp/runtime-packages.disallowed && \
    mkdir -p /runtime-root && \
    cp -a /bin /etc /lib /sbin /usr /var /app /runtime-root/ && \
    if [ -e /lib64 ]; then cp -a /lib64 /runtime-root/; fi && \
    while read -r pkg; do dpkg-query -L "$pkg" 2>/dev/null || true; done < /tmp/runtime-packages.disallowed | \
      grep '^/' | while read -r path; do \
        keep=0; \
        for owner in $(dpkg-query -S "$path" 2>/dev/null | cut -d: -f1 | tr ',' '\n' | sed 's/^[[:space:]]*//' | sort -u); do \
          if grep -Fxq "$owner" /tmp/runtime-packages.requested; then keep=1; break; fi; \
        done; \
        target="/runtime-root${path}"; \
        if [ "$keep" -eq 0 ] && { [ -f "$target" ] || [ -L "$target" ]; }; then rm -f "$target"; fi; \
      done && \
    rm -rf /runtime-root/etc/apt \
           /runtime-root/etc/bash.bashrc \
           /runtime-root/etc/dpkg \
           /runtime-root/var/cache/apt \
           /runtime-root/var/lib/apt \
           /runtime-root/var/lib/dpkg \
           /runtime-root/var/log/apt \
           /runtime-root/var/log/dpkg.log \
           /runtime-root/usr/lib/dpkg \
           /runtime-root/usr/libexec/dpkg \
           /runtime-root/usr/sbin/dpkg-preconfigure \
           /runtime-root/usr/sbin/dpkg-reconfigure \
           /runtime-root/usr/share/doc/bash \
           /runtime-root/usr/share/doc/dpkg \
           /runtime-root/usr/share/dpkg \
           /runtime-root/usr/share/lintian/profiles/dpkg \
           /runtime-root/var/lib/systemd/deb-systemd-helper-enabled/dpkg-db-backup.timer.dsh-also \
           /runtime-root/var/lib/systemd/deb-systemd-helper-enabled/timers.target.wants/dpkg-db-backup.timer \
           /runtime-root/etc/systemd/system/timers.target.wants/dpkg-db-backup.timer && \
    find /runtime-root \( -type f -o -type l \) | \
      sed 's#^/runtime-root##' | \
      while read -r path; do \
        owners=$(dpkg-query -S "$path" 2>/dev/null | cut -d: -f1 | tr ',' '\n' | sed 's/^[[:space:]]*//' | sed '/^$/d' | sort -u); \
        selected=$(printf '%s\n' "$owners" | while read -r owner; do \
          if grep -Fxq "$owner" /tmp/runtime-packages.requested; then printf '%s\n' "$owner"; fi; \
        done); \
        if [ -n "$selected" ]; then \
          printf '%s\n' "$selected"; \
        else \
          printf '%s\n' "$owners"; \
        fi; \
      done | sort -u > /runtime-root/app/.package-manifest && \
    chown appuser:appuser /runtime-root/app && \
    mkdir -p /runtime-root/tmp && \
    chmod 1777 /runtime-root/tmp

# --- Runtime variant: final image assembled from curated Debian runtime files ---
FROM scratch AS runtime

COPY --from=runtime-prep /runtime-root/ /

ARG BUILD_DATE
ARG VCS_REF

LABEL org.opencontainers.image.source="https://github.com/mattcurf/container_ci" \
      org.opencontainers.image.description="Minimal hardened Debian bookworm base image (runtime)" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.created="${BUILD_DATE}"

ENV LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
ENV TZ=Etc/UTC

WORKDIR /app
HEALTHCHECK NONE
USER appuser
CMD ["/bin/sh"]
