ARG BUILD_FROM
FROM ${BUILD_FROM}

ENV LANG=C.UTF-8

# Install a JRE (Eclipse Temurin LTS) plus the tools run.sh needs to resolve
# versions and download mods at runtime: curl + jq.
RUN \
    apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        gnupg \
        jq \
    && mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://packages.adoptium.net/artifactory/api/gpg/key/public \
        | gpg --dearmor -o /etc/apt/keyrings/adoptium.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/adoptium.gpg] https://packages.adoptium.net/artifactory/deb bookworm main" \
        > /etc/apt/sources.list.d/adoptium.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends temurin-25-jre \
    && apt-get purge -y --auto-remove gnupg \
    && rm -rf /var/lib/apt/lists/*

COPY rootfs/run.sh /run.sh
RUN chmod +x /run.sh

# Java Edition (TCP) and Bedrock/Geyser (UDP)
EXPOSE 25565/tcp
EXPOSE 19132/udp

CMD ["/run.sh"]
