#!/bin/bash
# Main add-on entry point.
# Sources all server-type scripts (function definitions), then dispatches to
# the appropriate prepare_* function, starts the web dashboard, and manages
# the server process lifecycle.
# shellcheck disable=SC1091
set -euo pipefail

SERVERS_DIR="${SERVERS_DIR:-/servers}"

source "${SERVERS_DIR}/common.sh"
source "${SERVERS_DIR}/run_fabric.sh"
source "${SERVERS_DIR}/run_vanilla.sh"
source "${SERVERS_DIR}/run_paper.sh"
source "${SERVERS_DIR}/run_purpur.sh"
source "${SERVERS_DIR}/run_forge.sh"
source "${SERVERS_DIR}/run_bds.sh"
source "${SERVERS_DIR}/run_eaglercraft.sh"

# ---------------------------------------------------------------------------
# Process-communication paths
# ---------------------------------------------------------------------------
LOG_FILE="${LOG_FILE:-/tmp/mc.log}"
STDIN_PIPE="${STDIN_PIPE:-/tmp/mc_stdin}"
STATUS_FILE="${STATUS_FILE:-/tmp/mc_status.json}"

# PIDs managed by cleanup()
MC_PID=""
DASH_PID=""

cleanup() {
    [[ -n "${DASH_PID}" ]] && kill "${DASH_PID}" 2>/dev/null || true
    [[ -n "${MC_PID}" ]]   && kill "${MC_PID}"   2>/dev/null || true
    wait 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    local server_type
    server_type="$(opt server_type)"
    [[ -z "${server_type}" ]] && server_type="fabric"   # backward-compat default

    mkdir -p "${SERVER_DIR}" "${ADDON_CONFIG_DIR}" "${DATA_DIR}"

    # Keep the FIFO open so the server never reads EOF when no client is writing.
    [[ -p "${STDIN_PIPE}" ]] || mkfifo "${STDIN_PIPE}"
    exec 3<>"${STDIN_PIPE}"

    # Common setup (skipped for BDS which has its own property/permissions format)
    if [[ "${server_type}" != "bds" ]]; then
        link_config_files
        handle_eula
        sync_runtime_config
        write_server_properties
        apply_ops
        apply_whitelist
        prepare_world
        build_jvm_args
    fi

    # Dispatch to the chosen server type
    case "${server_type}" in
        vanilla)     prepare_vanilla ;;
        paper)       prepare_paper ;;
        purpur)      prepare_purpur ;;
        fabric)      prepare_fabric ;;
        forge)       prepare_forge ;;
        bds)         prepare_bds ;;
        eaglercraft) prepare_eaglercraft ;;
        *)
            bashio::log.fatal "Unknown server_type '${server_type}'. Valid types: vanilla paper purpur fabric forge bds eaglercraft"
            exit 1
            ;;
    esac

    # Write status file for the dashboard
    jq -n \
        --arg type   "${server_type}" \
        --arg ver    "${MC_VERSION:-unknown}" \
        --argjson mp "$(opt max_players 2>/dev/null || echo 20)" \
        '{"server_type":$type,"mc_version":$ver,"max_players":$mp,"status":"starting"}' \
        > "${STATUS_FILE}" 2>/dev/null || true

    # Start dashboard (fails non-fatally if Python or aiohttp is missing)
    export MC_LOG_FILE="${LOG_FILE}"
    export MC_STDIN_PIPE="${STDIN_PIPE}"
    export MC_STATUS_FILE="${STATUS_FILE}"
    if command -v python3 >/dev/null 2>&1 && python3 -c "import aiohttp" 2>/dev/null; then
        python3 /dashboard/server.py &
        DASH_PID=$!
        bashio::log.info "Dashboard started (PID ${DASH_PID})."
    else
        bashio::log.warning "Python3/aiohttp not available; dashboard disabled."
    fi

    trap cleanup EXIT TERM INT

    # Change to the server's working directory
    [[ -n "${SERVER_WORKDIR:-}" ]] && cd "${SERVER_WORKDIR}"

    bashio::log.info "Starting ${server_type} server (Minecraft ${MC_VERSION:-unknown})..."

    # Run the server; tee mirrors all output to both the log file and container stdout.
    "${SERVER_LAUNCH[@]}" < "${STDIN_PIPE}" > >(tee -a "${LOG_FILE}") 2>&1 &
    MC_PID=$!

    wait "${MC_PID}"
    local exit_code=$?

    cleanup
    exit "${exit_code}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi
