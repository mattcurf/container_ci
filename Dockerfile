FROM debian:bookworm-slim

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

RUN groupadd -r appuser && useradd -r -g appuser -u 1000 -m -d /app -s /bin/bash appuser

ENV LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
ENV TZ=Etc/UTC

WORKDIR /app

HEALTHCHECK NONE

USER appuser

CMD ["/bin/bash"]
