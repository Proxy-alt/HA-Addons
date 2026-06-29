#!/bin/bash
# shellcheck disable=SC1091
set -euo pipefail

source "${BASHIO_LIB:-/usr/lib/bashio/bashio.sh}"

OPTIONS="${OPTIONS:-/data/options.json}"

# Uses select(. != null) so boolean false is returned as "false" rather than
# being silently discarded by jq's // empty alternative operator.
opt() { jq -r --arg k "$1" '.[$k] | select(. != null)' "${OPTIONS}"; }

# ---------------------------------------------------------------------------
# Data directory — playit stores its config under $HOME/.config/playit/
# Redirect HOME to the persistent data volume so config survives restarts.
# ---------------------------------------------------------------------------
export HOME="${PLAYIT_HOME:-/data}"
mkdir -p "${HOME}/.config/playit"

# ---------------------------------------------------------------------------
# Secret key — optional on first run; playit will print a claim URL if unset
# ---------------------------------------------------------------------------
SECRET_KEY="$(opt secret_key)"
if [[ -n "${SECRET_KEY}" ]]; then
    export PLAYIT_SECRET="${SECRET_KEY}"
    bashio::log.info "Starting Playit.gg agent..."
else
    bashio::log.warning "No secret key configured."
    bashio::log.warning "Playit.gg will print a claim URL — check the add-on Log tab."
    bashio::log.warning "Visit the URL, claim this agent at app.playit.gg, then paste"
    bashio::log.warning "the generated secret key into the add-on configuration and restart."
fi

# ---------------------------------------------------------------------------
# Start the playit agent
# ---------------------------------------------------------------------------
exec "${PLAYIT_BIN:-/usr/local/bin/playit}"
