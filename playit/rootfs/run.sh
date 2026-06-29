#!/bin/bash
# shellcheck disable=SC1091
set -euo pipefail

source "${BASHIO_LIB:-/usr/lib/bashio/bashio.sh}"

OPTIONS="${OPTIONS:-/data/options.json}"

# Uses select(. != null) so boolean false is returned as "false" rather than
# being silently discarded by jq's // empty alternative operator.
opt() { jq -r --arg k "$1" '.[$k] | select(. != null)' "${OPTIONS}"; }

# ---------------------------------------------------------------------------
# Paths — both overridable for testing
# ---------------------------------------------------------------------------
SECRET_PATH="${SECRET_PATH:-/data/playit.toml}"
SOCKET_DIR="${SOCKET_DIR:-/run/playit}"
SOCKET_PATH="${SOCKET_DIR}/playitd.sock"

mkdir -p "${SOCKET_DIR}"

# ---------------------------------------------------------------------------
# Secret key — write TOML secret file when provided.
# On first run with no key, playitd prints a claim URL to stdout; the user
# claims the agent at app.playit.gg and playitd writes the secret itself.
# The /data volume persists the file across restarts so re-claiming is not
# needed after the initial setup.
# ---------------------------------------------------------------------------
SECRET_KEY="$(opt secret_key)"
if [[ -n "${SECRET_KEY}" ]]; then
    printf 'secret_key = "%s"\n' "${SECRET_KEY}" > "${SECRET_PATH}"
    bashio::log.info "Starting Playit.gg agent with configured secret key..."
else
    bashio::log.warning "No secret key configured."
    bashio::log.warning "Playit.gg will print a claim URL — check the add-on Log tab."
    bashio::log.warning "Visit the URL to claim this agent at app.playit.gg."
    bashio::log.warning "The secret is then saved automatically and persists across restarts."
fi

# ---------------------------------------------------------------------------
# Start the playit daemon
# ---------------------------------------------------------------------------
exec "${PLAYITD_BIN:-/usr/local/bin/playitd}" \
    --secret-path "${SECRET_PATH}" \
    --socket-path "${SOCKET_PATH}"
