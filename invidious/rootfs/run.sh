#!/bin/bash
# shellcheck disable=SC1091
set -euo pipefail

source /usr/lib/bashio/bashio.sh

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
PGDATA="/data/postgres"
INVIDIOUS_BIN="/opt/invidious/invidious"
CONFIG_DIR="/data/invidious"
CONFIG_FILE="${CONFIG_DIR}/config.yml"
HMAC_KEY_FILE="${CONFIG_DIR}/.hmac_key"

PG_PID=""
INV_PID=""

# ---------------------------------------------------------------------------
# Graceful shutdown
# ---------------------------------------------------------------------------
cleanup() {
    bashio::log.info "Shutting down..."
    if [[ -n "${INV_PID}" ]] && kill -0 "${INV_PID}" 2>/dev/null; then
        kill -TERM "${INV_PID}" 2>/dev/null || true
        wait "${INV_PID}" 2>/dev/null || true
    fi
    if [[ -n "${PG_PID}" ]] && kill -0 "${PG_PID}" 2>/dev/null; then
        gosu postgres pg_ctl stop -D "${PGDATA}" -m fast -w 2>/dev/null || true
        wait "${PG_PID}" 2>/dev/null || true
    fi
}
trap cleanup EXIT SIGTERM SIGINT SIGQUIT

# ---------------------------------------------------------------------------
# PostgreSQL — initialise data directory on first run
# ---------------------------------------------------------------------------
if [[ ! -f "${PGDATA}/PG_VERSION" ]]; then
    bashio::log.info "Initialising PostgreSQL data directory..."
    mkdir -p "${PGDATA}"
    chown -R postgres:postgres "${PGDATA}"
    gosu postgres initdb \
        --pgdata="${PGDATA}" \
        --encoding=UTF8 \
        --locale=C.UTF-8 \
        --auth-local=trust \
        --auth-host=trust \
        --no-sync
    bashio::log.info "PostgreSQL initialised."
fi

# ---------------------------------------------------------------------------
# PostgreSQL — start
# ---------------------------------------------------------------------------
bashio::log.info "Starting PostgreSQL..."
chown -R postgres:postgres /run/postgresql

gosu postgres postgres \
    -D "${PGDATA}" \
    -c listen_addresses=127.0.0.1 \
    -c logging_collector=off \
    &
PG_PID=$!

# ---------------------------------------------------------------------------
# PostgreSQL — wait until ready
# ---------------------------------------------------------------------------
bashio::log.info "Waiting for PostgreSQL to accept connections..."
TIMEOUT=60
for i in $(seq 1 "${TIMEOUT}"); do
    if gosu postgres pg_isready -h 127.0.0.1 -p 5432 -q 2>/dev/null; then
        bashio::log.info "PostgreSQL is ready."
        break
    fi
    if [[ "${i}" -eq "${TIMEOUT}" ]]; then
        bashio::log.fatal "PostgreSQL did not become ready within ${TIMEOUT} seconds."
        exit 1
    fi
    sleep 1
done

# ---------------------------------------------------------------------------
# PostgreSQL — create database and user on first run
# ---------------------------------------------------------------------------
if ! gosu postgres psql -lqt 2>/dev/null | cut -d '|' -f 1 | grep -qw invidious; then
    bashio::log.info "Creating Invidious database..."
    gosu postgres psql -v ON_ERROR_STOP=1 <<-EOSQL
        CREATE USER kemal WITH PASSWORD 'kemal';
        CREATE DATABASE invidious OWNER kemal ENCODING 'UTF8';
EOSQL
    gosu postgres psql -v ON_ERROR_STOP=1 -d invidious <<-EOSQL
        CREATE EXTENSION IF NOT EXISTS pg_trgm;
EOSQL
    bashio::log.info "Database created."
fi

# ---------------------------------------------------------------------------
# Invidious — build configuration from add-on options
# ---------------------------------------------------------------------------
mkdir -p "${CONFIG_DIR}"

HMAC_KEY="$(bashio::config 'hmac_key')" || HMAC_KEY=""
if [[ -z "${HMAC_KEY}" ]]; then
    if [[ -f "${HMAC_KEY_FILE}" ]]; then
        HMAC_KEY="$(cat "${HMAC_KEY_FILE}")"
    else
        HMAC_KEY="$(openssl rand -hex 32)"
        echo "${HMAC_KEY}" > "${HMAC_KEY_FILE}"
        chmod 600 "${HMAC_KEY_FILE}"
        bashio::log.info "Generated new HMAC key."
    fi
fi

DOMAIN="$(bashio::config 'domain')" || DOMAIN=""
HTTPS_ONLY="$(bashio::config 'https_only')"
REGISTRATION_ENABLED="$(bashio::config 'registration_enabled')"
LOGIN_ENABLED="$(bashio::config 'login_enabled')"
DEFAULT_HOME="$(bashio::config 'default_home')"
CHANNEL_THREADS="$(bashio::config 'channel_threads')"
FEED_THREADS="$(bashio::config 'feed_threads')"

bashio::log.info "Writing Invidious configuration..."
cat > "${CONFIG_FILE}" <<EOF
channel_threads: ${CHANNEL_THREADS}
feed_threads: ${FEED_THREADS}

db:
  user: kemal
  password: kemal
  host: 127.0.0.1
  port: 5432
  dbname: invidious

full_refresh: false
https_only: ${HTTPS_ONLY}
domain: "${DOMAIN}"
hmac_key: "${HMAC_KEY}"

port: 3000
host_binding: "0.0.0.0"

registration_enabled: ${REGISTRATION_ENABLED}
login_enabled: ${LOGIN_ENABLED}

default_home: "${DEFAULT_HOME}"
feed_menu:
EOF

# Append each feed_menu entry (options.json array → YAML list)
jq -r '.feed_menu[]' /data/options.json | while IFS= read -r item; do
    printf '  - "%s"\n' "${item}" >> "${CONFIG_FILE}"
done

# ---------------------------------------------------------------------------
# Invidious — start
# ---------------------------------------------------------------------------
bashio::log.info "Starting Invidious on port 3000..."
cd /opt/invidious
"${INVIDIOUS_BIN}" --config "${CONFIG_FILE}" &
INV_PID=$!

bashio::log.info "Invidious is running (PID ${INV_PID})."

# ---------------------------------------------------------------------------
# Monitor both processes — exit if either dies
# ---------------------------------------------------------------------------
wait -n "${PG_PID}" "${INV_PID}"
EXIT_CODE=$?
bashio::log.error "A monitored process exited (code ${EXIT_CODE}). Stopping add-on."
exit "${EXIT_CODE}"
