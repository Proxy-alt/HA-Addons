ARG BUILD_FROM
FROM ${BUILD_FROM}

ENV LANG=C.UTF-8

ARG TARGETARCH

# Install runtime dependencies and download the playit agent binary.
# Release assets follow the Rust target-triple naming convention:
#   https://github.com/playit-cloud/playit-program/releases
ARG PLAYIT_VERSION="0.15.26"
RUN \
    apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        jq \
    && rm -rf /var/lib/apt/lists/* \
    && case "${TARGETARCH}" in \
        amd64) PLAYIT_ARCH="x86_64-unknown-linux-musl"  ;; \
        arm64) PLAYIT_ARCH="aarch64-unknown-linux-musl" ;; \
        *) echo "Unsupported architecture: ${TARGETARCH}" && exit 1 ;; \
    esac \
    && curl -fsSL \
        "https://github.com/playit-cloud/playit-program/releases/download/v${PLAYIT_VERSION}/playit-${PLAYIT_ARCH}" \
        -o /usr/local/bin/playit \
    && chmod +x /usr/local/bin/playit

COPY rootfs/run.sh /run.sh
RUN chmod +x /run.sh

CMD ["/run.sh"]
