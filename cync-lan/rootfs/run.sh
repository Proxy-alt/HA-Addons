#!/bin/bash
# shellcheck disable=SC1091
set -euo pipefail

source "${BASHIO_LIB:-/usr/lib/bashio/bashio.sh}"

OPTIONS="${OPTIONS:-/data/options.json}"
CONFIG_DIR="${CONFIG_DIR:-/data/config}"
CERTS_DIR="${CERTS_DIR:-/data/certs}"
SUPERVISOR_API="${SUPERVISOR_API:-http://supervisor}"
CYNC_LAN_BIN="${CYNC_LAN_BIN:-cync-lan}"

SECRET_KEY=""

# Uses select(. != null) so that boolean false is returned as "false" rather
# than being silently discarded by jq's // empty alternative operator.
opt() { jq -r --arg k "$1" '.[$k] | select(. != null)' "${OPTIONS}"; }

# Reads a list option and joins it into a comma-separated string.
opt_list() { jq -r --arg k "$1" '.[$k] // [] | join(",")' "${OPTIONS}"; }

# ---------------------------------------------------------------------------
# Persist a derived option back to the add-on configuration.
#
# The Supervisor's POST /addons/self/options endpoint *replaces* the stored
# options, so we read the current effective options from ${OPTIONS}, set the
# one key, and send the whole object back. The change then shows up in the
# Home Assistant UI and survives restarts.
#
# No-op (with a warning) when SUPERVISOR_TOKEN is unset — e.g. during tests or
# when the API is unreachable — so a sync failure never blocks startup.
# ---------------------------------------------------------------------------
persist_option() {
    local key="$1" value="$2"

    # Already stored — nothing to write.
    [[ "$(opt "${key}")" == "${value}" ]] && return 0

    if [[ -z "${SUPERVISOR_TOKEN:-}" ]]; then
        bashio::log.warning "SUPERVISOR_TOKEN not set; cannot save '${key}' to the add-on options."
        return 0
    fi

    local payload
    payload="$(jq -c --arg k "${key}" --arg v "${value}" '{options: (. + {($k): $v})}' "${OPTIONS}")" || {
        bashio::log.warning "Could not build options payload for '${key}'; skipping write-back."
        return 0
    }

    if curl -fsSL -X POST \
        -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "${payload}" \
        "${SUPERVISOR_API}/addons/self/options" >/dev/null 2>&1; then
        bashio::log.info "Saved '${key}' to the add-on options."
    else
        bashio::log.warning "Failed to save '${key}' via the Supervisor API."
    fi
}

# ---------------------------------------------------------------------------
# Secret key — cync-lan uses this to encrypt the cached Cync cloud auth token
# at rest. Resolved the same way Invidious resolves its hmac_key: use the
# configured value, fall back to a value persisted from a previous run, or
# generate and persist a new one.
# ---------------------------------------------------------------------------
resolve_secret_key() {
    local secret_key_file="${CONFIG_DIR}/.secret_key"

    mkdir -p "${CONFIG_DIR}"

    SECRET_KEY="$(opt secret_key)"
    if [[ -z "${SECRET_KEY}" ]]; then
        [[ -f "${secret_key_file}" ]] && SECRET_KEY="$(< "${secret_key_file}")"
        if [[ -z "${SECRET_KEY}" ]]; then
            SECRET_KEY="$(openssl rand -hex 32)"
            printf '%s' "${SECRET_KEY}" > "${secret_key_file}"
            chmod 600 "${secret_key_file}"
            bashio::log.info "Generated new secret key."
        fi
    fi

    if [[ -z "${SECRET_KEY}" ]]; then
        bashio::log.fatal "Secret key could not be resolved. Cannot start Cync LAN."
        return 1
    fi
}

# ---------------------------------------------------------------------------
# TLS certificate for device connections.
#
# Cync devices don't validate the CA, only that the TLS handshake succeeds,
# so a cert generated once per install and persisted to /data is used here
# rather than a fixed cert baked into the image and shared by every install
# that pulls it.
# ---------------------------------------------------------------------------
generate_certs() {
    mkdir -p "${CERTS_DIR}"

    if [[ -f "${CERTS_DIR}/cert.pem" && -f "${CERTS_DIR}/key.pem" ]]; then
        return 0
    fi

    bashio::log.info "Generating a self-signed TLS certificate for device connections..."
    openssl req -x509 -newkey rsa:4096 \
        -keyout "${CERTS_DIR}/key.pem" -out "${CERTS_DIR}/cert.pem" \
        -subj '/CN=cm.gelighting.com' \
        -addext 'subjectAltName=DNS:cm.gelighting.com,DNS:cm-sec.gelighting.com,DNS:cm-ge.xlink.cn,DNS:*.xlink.cn' \
        -sha256 -days 3650 -nodes >/dev/null 2>&1
    chmod 600 "${CERTS_DIR}/key.pem"
}

# ---------------------------------------------------------------------------
# Export add-on options as the environment variables cync-lan reads.
# ---------------------------------------------------------------------------
configure_env() {
    export CYNC_CONFIG_DIR="${CONFIG_DIR}"
    export CYNC_DEVICE_CERT="${CERTS_DIR}/cert.pem"
    export CYNC_DEVICE_KEY="${CERTS_DIR}/key.pem"
    export CYNC_SECRET_KEY="${SECRET_KEY}"
    export CYNC_ACCOUNT_USERNAME="$(opt account_username)"
    export CYNC_ACCOUNT_PASSWORD="$(opt account_password)"
    export CYNC_ENABLE_EXPORTER="$(opt enable_exporter)"
    export CYNC_MQTT_HOST="$(opt mqtt_host)"
    export CYNC_MQTT_PORT="$(opt mqtt_port)"
    export CYNC_MQTT_USER="$(opt mqtt_user)"
    export CYNC_MQTT_PASS="$(opt mqtt_password)"
    export CYNC_TOPIC="$(opt mqtt_topic)"
    export CYNC_MAX_TCP_CONN="$(opt max_tcp_connections)"
    export CYNC_CLOUD_IP="$(opt cloud_ip)"
    export CYNC_DEBUG="$(opt debug)"

    local whitelist
    whitelist="$(opt_list tcp_whitelist)"
    [[ -n "${whitelist}" ]] && export CYNC_TCP_WHITELIST="${whitelist}"

    if [[ "${CYNC_ENABLE_EXPORTER}" == "true" ]] \
        && { [[ -z "${CYNC_ACCOUNT_USERNAME}" ]] || [[ -z "${CYNC_ACCOUNT_PASSWORD}" ]]; }; then
        bashio::log.warning "Device export is enabled but no Cync account credentials are configured."
        bashio::log.warning "The export web UI will not be able to reach the Cync cloud API until they are set."
    fi
}

main() {
    generate_certs
    resolve_secret_key
    persist_option secret_key "${SECRET_KEY}"
    configure_env

    bashio::log.info "Starting Cync LAN on port 23779 (export UI on 23778)..."
    exec "${CYNC_LAN_BIN}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi
