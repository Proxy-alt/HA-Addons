ARG BUILD_FROM
FROM ${BUILD_FROM}

ENV LANG=C.UTF-8

ARG TARGETARCH

# Extract playitd from the official .deb package.
# The .deb ships both the CLI (playit) and the daemon (playitd);
# only the daemon is needed for headless operation.
ARG PLAYIT_VERSION="1.0.10"
RUN \
    apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        jq \
    && rm -rf /var/lib/apt/lists/* \
    && case "${TARGETARCH}" in \
        amd64) PLAYIT_DEB_ARCH="amd64" ;; \
        arm64) PLAYIT_DEB_ARCH="arm64" ;; \
        *) echo "Unsupported architecture: ${TARGETARCH}" && exit 1 ;; \
    esac \
    && curl -fsSL \
        "https://github.com/playit-cloud/playit-agent/releases/download/v${PLAYIT_VERSION}/playit_${PLAYIT_DEB_ARCH}.deb" \
        -o /tmp/playit.deb \
    && dpkg -x /tmp/playit.deb /tmp/playit-pkg \
    && cp /tmp/playit-pkg/opt/playit/playitd /usr/local/bin/playitd \
    && chmod +x /usr/local/bin/playitd \
    && rm -rf /tmp/playit.deb /tmp/playit-pkg

COPY rootfs/run.sh /run.sh
RUN chmod +x /run.sh

CMD ["/run.sh"]
