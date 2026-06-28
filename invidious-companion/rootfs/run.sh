#!/bin/bash
# shellcheck disable=SC1091
set -euo pipefail

source "${BASHIO_LIB:-/usr/lib/bashio/bashio.sh}"

OPTIONS="${OPTIONS:-/data/options.json}"

# Uses select(. != null) so boolean false is returned as "false" rather than
# being silently discarded by jq's // empty alternative operator.
opt() { jq -r --arg k "$1" '.[$k] | select(. != null)' "${OPTIONS}"; }

# ---------------------------------------------------------------------------
# Companion Key — required
# ---------------------------------------------------------------------------
COMPANION_KEY="$(opt companion_key)"
if [[ -z "${COMPANION_KEY}" ]]; then
    bashio::log.fatal "Companion Key is not set."
    bashio::log.fatal "Set it to a 16-character secret that matches the Companion API Key"
    bashio::log.fatal "configured in the Invidious add-on."
    exit 1
fi
export COMPANION_KEY

# ---------------------------------------------------------------------------
# Performance
# ---------------------------------------------------------------------------
export BACKEND_VIDEO_DOWNLOAD_THREADS="$(opt download_threads)"

# ---------------------------------------------------------------------------
# Server binding (env var names used by the official companion image)
# ---------------------------------------------------------------------------
export PORT="8282"
export HOST="0.0.0.0"

# ---------------------------------------------------------------------------
# Outbound proxy — HTTP
# ---------------------------------------------------------------------------
HTTP_PROXY_URL="$(opt http_proxy)"
if [[ -n "${HTTP_PROXY_URL}" ]]; then
    export HTTP_PROXY="${HTTP_PROXY_URL}"
    export http_proxy="${HTTP_PROXY_URL}"
fi

# ---------------------------------------------------------------------------
# Outbound proxy — SOCKS
# ---------------------------------------------------------------------------
SOCKS_HOST="$(opt socks_proxy_host)"
if [[ -n "${SOCKS_HOST}" ]]; then
    export SOCKS_PROXY="${SOCKS_HOST}"
    export SOCKS_PORT="$(opt socks_proxy_port)"
fi

# ---------------------------------------------------------------------------
# Start Invidious Companion
# ---------------------------------------------------------------------------
bashio::log.info "Starting Invidious Companion on port 8282..."
exec "${TINI_BIN:-/usr/local/bin/tini}" -- "${COMPANION_BIN:-/usr/local/bin/invidious_companion}"
