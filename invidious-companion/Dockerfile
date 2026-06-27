# Stage 1: pull official Invidious Companion image for the target architecture
ARG BUILD_FROM
FROM --platform=$TARGETPLATFORM quay.io/invidious/invidious-companion:latest AS companion-src

# Stage 2: HA Debian base
FROM ${BUILD_FROM}

ENV LANG=C.UTF-8

RUN \
    apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        jq \
    && rm -rf /var/lib/apt/lists/*

# Copy Invidious Companion binary and tini from official image.
# Binary is at /app/invidious_companion; tini is used as PID 1.
COPY --from=companion-src /app/invidious_companion /usr/local/bin/invidious_companion
COPY --from=companion-src /tini /usr/local/bin/tini

COPY rootfs/run.sh /run.sh
RUN chmod +x /run.sh

EXPOSE 8282

CMD ["/run.sh"]
