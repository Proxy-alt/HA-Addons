#!/bin/bash
# shellcheck disable=SC1091
set -euo pipefail

source "${BASHIO_LIB:-/usr/lib/bashio/bashio.sh}"

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
PGDATA="/data/postgres"
INVIDIOUS_BIN="/opt/invidious/invidious"
CONFIG_DIR="/data/invidious"
# Keep the generated config on the persistent /data volume. Invidious writes
# admin-UI preference changes back to "config/config.yml" relative to its
# working dir; CONFIG_LINK is symlinked to CONFIG_FILE so those writes land on
# /data and survive container restarts/updates.
CONFIG_FILE="${CONFIG_DIR}/config.yml"
CONFIG_LINK="/opt/invidious/config/config.yml"
# Snapshot of the options last used to generate CONFIG_FILE. We regenerate only
# when the HA options actually change, so preference changes made through the
# Invidious admin web UI are preserved across restarts.
OPTIONS_SNAPSHOT="${CONFIG_DIR}/.last_options.json"
OPTIONS="/data/options.json"
SUPERVISOR_API="${SUPERVISOR_API:-http://supervisor}"

PG_PID=""
INV_PID=""
HMAC_KEY=""

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Read a scalar option from options.json by key name.
# Uses select(. != null) so that boolean false is returned as "false"
# rather than silently discarded the way jq's // empty operator behaves.
opt() { jq -r --arg k "$1" '.[$k] | select(. != null)' "${OPTIONS}"; }

# Read a float option and guarantee the output has a decimal point.
# jq 1.6 (Debian 12) outputs integer-valued floats without a decimal
# (e.g. 1.0 → "1"). Crystal's YAML parser rejects bare integers for
# Float64 fields, so we must ensure "1" becomes "1.0".
opt_float() {
    local val
    val="$(opt "$1")"
    [[ "${val}" =~ ^-?[0-9]+$ ]] && val="${val}.0"
    printf '%s' "${val}"
}

# Output a YAML value that can be a YAML boolean or quoted string.
# Use for fields where Invidious accepts true/false OR a string keyword.
yaml_bool_or_str() {
    local val="$1"
    if [[ "${val}" == "true" || "${val}" == "false" ]]; then
        printf '%s' "${val}"
    else
        printf '"%s"' "${val}"
    fi
}

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

# ---------------------------------------------------------------------------
# Invidious — resolve HMAC key
# ---------------------------------------------------------------------------
resolve_hmac_key() {
    local hmac_key_file="${CONFIG_DIR}/.hmac_key"

    mkdir -p "${CONFIG_DIR}"

    HMAC_KEY="$(opt hmac_key)"
    if [[ -z "${HMAC_KEY}" ]]; then
        [[ -f "${hmac_key_file}" ]] && HMAC_KEY="$(< "${hmac_key_file}")"
        if [[ -z "${HMAC_KEY}" ]]; then
            HMAC_KEY="$(openssl rand -hex 32)"
            printf '%s' "${HMAC_KEY}" > "${hmac_key_file}"
            chmod 600 "${hmac_key_file}"
            bashio::log.info "Generated new HMAC key."
        fi
    fi

    if [[ -z "${HMAC_KEY}" ]]; then
        bashio::log.fatal "HMAC key could not be resolved. Cannot start Invidious."
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Symlink Invidious's relative write path to the persistent config file so
# admin-UI preference changes (which Invidious saves to config/config.yml) are
# written to /data and survive restarts.
# ---------------------------------------------------------------------------
link_config() {
    mkdir -p "${CONFIG_DIR}" "$(dirname "${CONFIG_LINK}")"
    ln -sf "${CONFIG_FILE}" "${CONFIG_LINK}"
}

# ---------------------------------------------------------------------------
# True when a generated config already exists and the HA options have not
# changed since it was written. In that case we leave the file untouched so
# that preference changes made through the Invidious admin web UI are kept.
# ---------------------------------------------------------------------------
config_is_current() {
    [[ -f "${CONFIG_FILE}" ]] || return 1
    [[ -f "${OPTIONS_SNAPSHOT}" ]] || return 1
    jq -e -n --slurpfile a "${OPTIONS}" --slurpfile b "${OPTIONS_SNAPSHOT}" \
        '$a[0] == $b[0]' >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# Invidious — write configuration
# ---------------------------------------------------------------------------
write_invidious_config() {
    if config_is_current; then
        bashio::log.info "Add-on options unchanged; keeping existing Invidious config (preserving any admin web-UI changes)."
        return 0
    fi

    bashio::log.info "Writing Invidious configuration..."

    mkdir -p "${CONFIG_DIR}" "$(dirname "${CONFIG_FILE}")"

    {
# DATABASE
cat <<YAML
# Generated by Home Assistant Invidious Add-on — do not edit manually.

db:
  user: kemal
  password: kemal
  host: 127.0.0.1
  port: 5432
  dbname: invidious

check_tables: $(opt check_tables)

YAML

# SERVER
cat <<YAML
port: 3000
host_binding: "0.0.0.0"
hmac_key: "${HMAC_KEY}"
domain: "$(opt domain)"
https_only: $(opt https_only)
hsts: $(opt hsts)
YAML

EXTERNAL_PORT="$(opt external_port)"
if [[ -n "${EXTERNAL_PORT}" && "${EXTERNAL_PORT}" != "0" ]]; then
    printf 'external_port: %s\n' "${EXTERNAL_PORT}"
fi

if jq -e '.alternative_domains | length > 0' "${OPTIONS}" >/dev/null 2>&1; then
    printf 'alternative_domains:\n'
    jq -r '.alternative_domains[]' "${OPTIONS}" | while IFS= read -r d; do
        printf '  - "%s"\n' "${d}"
    done
fi

printf '\n'

# NETWORK (OUTBOUND)
printf 'disable_proxy: %s\n' "$(yaml_bool_or_str "$(opt disable_proxy)")"
printf 'pool_size: %s\n' "$(opt pool_size)"
printf 'use_innertube_for_captions: %s\n' "$(opt use_innertube_for_captions)"

FORCE_RESOLVE="$(opt force_resolve)"
if [[ -n "${FORCE_RESOLVE}" ]]; then
    printf 'force_resolve: %s\n' "${FORCE_RESOLVE}"
fi

COOKIES="$(opt cookies)"
if [[ -n "${COOKIES}" ]]; then
    printf 'cookies: "%s"\n' "${COOKIES}"
fi

HTTP_PROXY_HOST="$(opt http_proxy_host)"
if [[ -n "${HTTP_PROXY_HOST}" ]]; then
    printf 'http_proxy:\n'
    printf '  host: "%s"\n' "${HTTP_PROXY_HOST}"
    printf '  port: %s\n' "$(opt http_proxy_port)"
    HTTP_PROXY_USER="$(opt http_proxy_user)"
    HTTP_PROXY_PASS="$(opt http_proxy_password)"
    [[ -n "${HTTP_PROXY_USER}" ]] && printf '  user: "%s"\n' "${HTTP_PROXY_USER}"
    [[ -n "${HTTP_PROXY_PASS}" ]] && printf '  password: "%s"\n' "${HTTP_PROXY_PASS}"
fi

printf '\n'

# LOGGING
cat <<YAML
log_level: $(opt log_level)
output: STDOUT

YAML

# FEATURES
cat <<YAML
popular_enabled: $(opt popular_enabled)
statistics_enabled: $(opt statistics_enabled)

YAML

# USERS & ACCOUNTS
cat <<YAML
registration_enabled: $(opt registration_enabled)
login_enabled: $(opt login_enabled)
captcha_enabled: $(opt captcha_enabled)
enable_user_notifications: $(opt enable_user_notifications)
YAML

if jq -e '.admins | length > 0' "${OPTIONS}" >/dev/null 2>&1; then
    printf 'admins:\n'
    jq -r '.admins[]' "${OPTIONS}" | while IFS= read -r admin; do
        printf '  - "%s"\n' "${admin}"
    done
fi

printf '\n'

# BACKGROUND JOBS
cat <<YAML
channel_threads: $(opt channel_threads)
feed_threads: $(opt feed_threads)
channel_refresh_interval: $(opt channel_refresh_interval)
full_refresh: $(opt full_refresh)

jobs:
  clear_expired_items:
    enable: $(opt jobs_clear_expired_items)
  refresh_channels:
    enable: $(opt jobs_refresh_channels)
  refresh_feeds:
    enable: $(opt jobs_refresh_feeds)

YAML

# MISCELLANEOUS
BANNER="$(opt banner)"
[[ -n "${BANNER}" ]] && printf 'banner: "%s"\n' "${BANNER}"

cat <<YAML
cache_annotations: $(opt cache_annotations)
playlist_length_limit: $(opt playlist_length_limit)
YAML

# use_pubsub_feeds: accepts a YAML bool or a positive integer
USE_PUBSUB="$(opt use_pubsub_feeds)"
if [[ "${USE_PUBSUB}" =~ ^[0-9]+$ ]] || [[ "${USE_PUBSUB}" == "false" ]] || [[ "${USE_PUBSUB}" == "true" ]]; then
    printf 'use_pubsub_feeds: %s\n' "${USE_PUBSUB}"
else
    printf 'use_pubsub_feeds: false\n'
fi

if jq -e '.dmca_content | length > 0' "${OPTIONS}" >/dev/null 2>&1; then
    printf 'dmca_content:\n'
    jq -r '.dmca_content[]' "${OPTIONS}" | while IFS= read -r vid; do
        printf '  - "%s"\n' "${vid}"
    done
fi

printf '\n'

# INVIDIOUS COMPANION
COMPANION_PRIVATE="$(opt companion_private_url)"
if [[ -n "${COMPANION_PRIVATE}" ]]; then
    printf 'invidious_companion:\n'
    printf '  - private_url: "%s"\n' "${COMPANION_PRIVATE}"
    COMPANION_PUBLIC="$(opt companion_public_url)"
    [[ -n "${COMPANION_PUBLIC}" ]] && printf '    public_url: "%s"\n' "${COMPANION_PUBLIC}"
    printf 'invidious_companion_key: "%s"\n' "$(opt companion_key)"
    printf '\n'
fi

# DEFAULT USER PREFERENCES
cat <<YAML
default_user_preferences:
  locale: "$(opt locale)"
  region: "$(opt region)"
  dark_mode: "$(opt dark_mode)"
  thin_mode: $(opt thin_mode)
  default_home: "$(opt default_home)"
  max_results: $(opt max_results)
  annotations: $(opt annotations)
  annotations_subscribed: $(opt annotations_subscribed)
  player_style: "$(opt player_style)"
  related_videos: $(opt related_videos)
  preload: $(opt preload)
  autoplay: $(opt autoplay)
  continue: $(opt continue_videos)
  continue_autoplay: $(opt continue_autoplay)
  listen: $(opt listen)
  video_loop: $(opt video_loop)
  quality: "$(opt quality)"
  quality_dash: "$(opt quality_dash)"
  speed: $(opt_float speed)
  volume: $(opt volume)
  vr_mode: $(opt vr_mode)
  save_player_pos: $(opt save_player_pos)
  latest_only: $(opt latest_only)
  notifications_only: $(opt notifications_only)
  unseen_only: $(opt unseen_only)
  sort: "$(opt sort)"
  local: $(opt proxy_videos)
  show_nick: $(opt show_nick)
  automatic_instance_redirect: $(opt automatic_instance_redirect)
  extend_desc: $(opt extend_desc)
YAML

# feed_menu (list) — emit YAML empty sequence when the list has no items so
# Invidious receives [] rather than null.
if jq -e '.feed_menu | length > 0' "${OPTIONS}" >/dev/null 2>&1; then
    printf '  feed_menu:\n'
    jq -r '.feed_menu[]' "${OPTIONS}" | while IFS= read -r item; do
        printf '    - "%s"\n' "${item}"
    done
else
    printf '  feed_menu: []\n'
fi

# captions (fixed 3-item array)
printf '  captions:\n'
printf '    - "%s"\n' "$(opt caption_1)"
printf '    - "%s"\n' "$(opt caption_2)"
printf '    - "%s"\n' "$(opt caption_3)"

# comments (fixed 2-item array)
printf '  comments:\n'
printf '    - "%s"\n' "$(opt comments_1)"
printf '    - "%s"\n' "$(opt comments_2)"

    } > "${CONFIG_FILE}"

    # Record the options we generated from, so the next start can detect whether
    # the HA options changed (regenerate) or not (preserve admin web changes).
    cp "${OPTIONS}" "${OPTIONS_SNAPSHOT}"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
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
    mkdir -p /run/postgresql
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
    # Invidious — resolve HMAC key and write configuration
    # ---------------------------------------------------------------------------
    resolve_hmac_key
    # Reflect an auto-generated key back into the add-on options so it is
    # visible in the UI and reused as the canonical source going forward.
    persist_option hmac_key "${HMAC_KEY}"
    # Point Invidious's config write path at the persistent file before writing.
    link_config
    write_invidious_config

    # ---------------------------------------------------------------------------
    # Invidious — start
    # ---------------------------------------------------------------------------
    bashio::log.info "Starting Invidious on port 3000..."
    cd /opt/invidious
    INVIDIOUS_CONFIG_FILE="${CONFIG_FILE}" "${INVIDIOUS_BIN}" &
    INV_PID=$!

    bashio::log.info "Invidious is running (PID ${INV_PID})."

    # ---------------------------------------------------------------------------
    # Monitor both processes — exit if either dies
    # ---------------------------------------------------------------------------
    wait -n "${PG_PID}" "${INV_PID}"
    EXIT_CODE=$?
    bashio::log.error "A monitored process exited (code ${EXIT_CODE}). Stopping add-on."
    exit "${EXIT_CODE}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi
