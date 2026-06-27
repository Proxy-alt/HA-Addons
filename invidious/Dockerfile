# Stage 1: pull official Invidious image for the target architecture
ARG BUILD_FROM
FROM --platform=$TARGETPLATFORM quay.io/invidious/invidious:latest AS invidious-src

# Stage 2: HA Debian base with PostgreSQL
FROM ${BUILD_FROM}

ENV LANG=C.UTF-8

# Install PostgreSQL, gosu (privilege dropping), and Invidious runtime deps
RUN \
    apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        gosu \
        jq \
        libgc1 \
        libgmp10 \
        libevent-2.1-7 \
        libpcre2-8-0 \
        libpq5 \
        libssl3 \
        libyaml-0-2 \
        openssl \
        postgresql \
        postgresql-client \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /run/postgresql /var/log/postgresql \
    && chown postgres:postgres /run/postgresql /var/log/postgresql \
    && PG_BINDIR="$(ls -d /usr/lib/postgresql/*/bin | head -1)" \
    && ln -sf "${PG_BINDIR}/initdb"   /usr/local/bin/initdb \
    && ln -sf "${PG_BINDIR}/postgres" /usr/local/bin/postgres \
    && ln -sf "${PG_BINDIR}/pg_ctl"   /usr/local/bin/pg_ctl

# Copy Invidious binary and static assets from official image
COPY --from=invidious-src /invidious /opt/invidious

COPY rootfs/run.sh /run.sh
RUN chmod +x /run.sh

EXPOSE 3000

CMD ["/run.sh"]
