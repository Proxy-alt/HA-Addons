#!/bin/bash
# shellcheck disable=SC1091
set -euo pipefail

source "${BASHIO_LIB:-/usr/lib/bashio/bashio.sh}"

# ---------------------------------------------------------------------------
# Paths / endpoints (overridable for tests)
# ---------------------------------------------------------------------------
OPTIONS="${OPTIONS:-/data/options.json}"
SERVER_DIR="${SERVER_DIR:-/data/server}"
MODS_DIR="${SERVER_DIR}/mods"
MANAGED_FILE="${SERVER_DIR}/.managed_mods"
LAUNCHER_JAR="${SERVER_DIR}/fabric-server-launch.jar"
VERSION_MARKER="${SERVER_DIR}/.fabric_version"

FABRIC_META="${FABRIC_META:-https://meta.fabricmc.net/v2}"
MODRINTH_API="${MODRINTH_API:-https://api.modrinth.com/v2}"
MOJANG_API="${MOJANG_API:-https://api.mojang.com}"
JAVA_BIN="${JAVA_BIN:-java}"
SUPERVISOR_API="${SUPERVISOR_API:-http://supervisor}"

# Baselines recording the last set we synced for each managed list option, so
# a three-way merge can tell whether an entry was added or removed in-game
# (in the live JSON) versus in the Home Assistant UI (in the options).
OPS_BASELINE="${SERVER_DIR}/.synced_ops"
WHITELIST_BASELINE="${SERVER_DIR}/.synced_whitelist"

MC_VERSION=""
LOADER_VERSION=""
INSTALLER_VERSION=""

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Read a scalar option. select(. != null) keeps boolean false as "false"
# instead of letting jq's // empty discard it.
opt() { jq -r --arg k "$1" '.[$k] | select(. != null)' "${OPTIONS}"; }

# Resolve a Minecraft username to a hyphenated UUID via the Mojang API.
# Echoes the UUID and returns 0, or returns 1 when it cannot be resolved.
resolve_uuid() {
    local name="$1" prof id
    prof="$(curl -fsSL "${MOJANG_API}/users/profiles/minecraft/${name}" 2>/dev/null || true)"
    id="$(echo "${prof}" | jq -r '.id // empty' 2>/dev/null || true)"
    [[ -z "${id}" ]] && return 1
    printf '%s-%s-%s-%s-%s' "${id:0:8}" "${id:8:4}" "${id:12:4}" "${id:16:4}" "${id:20:12}"
}

# ---------------------------------------------------------------------------
# EULA — required
# ---------------------------------------------------------------------------
handle_eula() {
    if [[ "$(opt accept_eula)" != "true" ]]; then
        bashio::log.fatal "You must accept the Minecraft EULA to run this server."
        bashio::log.fatal "Set 'accept_eula: true' in the add-on configuration."
        bashio::log.fatal "EULA: https://aka.ms/MinecraftEULA"
        return 1
    fi
    echo "eula=true" > "${SERVER_DIR}/eula.txt"
}

# ---------------------------------------------------------------------------
# Resolve Minecraft / Fabric versions ("latest" → newest stable)
# ---------------------------------------------------------------------------
resolve_versions() {
    MC_VERSION="$(opt minecraft_version)"
    if [[ -z "${MC_VERSION}" || "${MC_VERSION}" == "latest" ]]; then
        MC_VERSION="$(curl -fsSL "${FABRIC_META}/versions/game" 2>/dev/null \
            | jq -r '[.[] | select(.stable)][0].version // empty')"
    fi

    LOADER_VERSION="$(opt fabric_loader_version)"
    if [[ -z "${LOADER_VERSION}" || "${LOADER_VERSION}" == "latest" ]]; then
        LOADER_VERSION="$(curl -fsSL "${FABRIC_META}/versions/loader" 2>/dev/null \
            | jq -r '[.[] | select(.stable)][0].version // empty')"
    fi

    INSTALLER_VERSION="$(curl -fsSL "${FABRIC_META}/versions/installer" 2>/dev/null \
        | jq -r '[.[] | select(.stable)][0].version // empty')"

    if [[ -z "${MC_VERSION}" || -z "${LOADER_VERSION}" || -z "${INSTALLER_VERSION}" ]]; then
        bashio::log.fatal "Could not resolve Fabric versions (Minecraft='${MC_VERSION}'," \
            "loader='${LOADER_VERSION}', installer='${INSTALLER_VERSION}')."
        bashio::log.fatal "Check the add-on's internet access and try again."
        return 1
    fi

    bashio::log.info "Minecraft ${MC_VERSION} · Fabric loader ${LOADER_VERSION} · installer ${INSTALLER_VERSION}"
}

# ---------------------------------------------------------------------------
# Download the Fabric server launcher (only when version changes)
# ---------------------------------------------------------------------------
download_server_jar() {
    local desired="${MC_VERSION}-${LOADER_VERSION}-${INSTALLER_VERSION}"
    if [[ -f "${LAUNCHER_JAR}" && "$(cat "${VERSION_MARKER}" 2>/dev/null)" == "${desired}" ]]; then
        bashio::log.info "Fabric server launcher already up to date."
        return 0
    fi

    local url="${FABRIC_META}/versions/loader/${MC_VERSION}/${LOADER_VERSION}/${INSTALLER_VERSION}/server/jar"
    bashio::log.info "Downloading Fabric server launcher..."
    if ! curl -fsSL -o "${LAUNCHER_JAR}.tmp" "${url}"; then
        bashio::log.fatal "Failed to download Fabric server launcher from ${url}"
        rm -f "${LAUNCHER_JAR}.tmp"
        return 1
    fi
    mv "${LAUNCHER_JAR}.tmp" "${LAUNCHER_JAR}"
    echo "${desired}" > "${VERSION_MARKER}"
}

# ---------------------------------------------------------------------------
# Download a single Modrinth mod (best effort — skip if unavailable)
# Picks the newest Fabric build matching the resolved Minecraft version.
# ---------------------------------------------------------------------------
download_mod() {
    local slug="$1"
    local url="${MODRINTH_API}/project/${slug}/version?loaders=%5B%22fabric%22%5D&game_versions=%5B%22${MC_VERSION}%22%5D"

    local json
    json="$(curl -fsSL "${url}" 2>/dev/null || true)"
    if [[ -z "${json}" || "$(echo "${json}" | jq 'length' 2>/dev/null || echo 0)" == "0" ]]; then
        bashio::log.warning "No '${slug}' build for Minecraft ${MC_VERSION}; skipping."
        return 0
    fi

    # Newest version, preferring its primary file.
    local picker='sort_by(.date_published) | reverse | .[0].files | (map(select(.primary)) + .)[0]'
    local file_url file_name
    file_url="$(echo "${json}" | jq -r "${picker}.url // empty")"
    file_name="$(echo "${json}" | jq -r "${picker}.filename // empty")"

    if [[ -z "${file_url}" || -z "${file_name}" ]]; then
        bashio::log.warning "Could not determine a download for '${slug}'; skipping."
        return 0
    fi

    if curl -fsSL -o "${MODS_DIR}/${file_name}" "${file_url}"; then
        echo "${file_name}" >> "${MANAGED_FILE}"
        bashio::log.info "Installed mod '${slug}' (${file_name})."
    else
        bashio::log.warning "Failed to download '${slug}'; skipping."
        rm -f "${MODS_DIR}/${file_name}"
    fi
}

# ---------------------------------------------------------------------------
# Synchronise the managed mod set with the current options
# ---------------------------------------------------------------------------
sync_mods() {
    mkdir -p "${MODS_DIR}"

    # Remove mods we installed previously (leaves user-dropped jars intact).
    if [[ -f "${MANAGED_FILE}" ]]; then
        while IFS= read -r f; do
            [[ -n "${f}" ]] && rm -f "${MODS_DIR}/${f}"
        done < "${MANAGED_FILE}"
    fi
    : > "${MANAGED_FILE}"

    local -a slugs=()
    [[ "$(opt mod_lithium)" == "true" ]]     && slugs+=("lithium")
    [[ "$(opt mod_ferritecore)" == "true" ]] && slugs+=("ferrite-core")
    [[ "$(opt mod_krypton)" == "true" ]]     && slugs+=("krypton")
    [[ "$(opt mod_c2me)" == "true" ]]        && slugs+=("c2me-fabric")
    [[ "$(opt mod_servercore)" == "true" ]]  && slugs+=("servercore")
    [[ "$(opt geyser_enabled)" == "true" ]]    && slugs+=("geyser")
    [[ "$(opt floodgate_enabled)" == "true" ]] && slugs+=("floodgate")

    while IFS= read -r s; do
        [[ -n "${s}" ]] && slugs+=("${s}")
    done < <(jq -r '.extra_mods[]?' "${OPTIONS}")

    # Fabric API is a dependency of effectively every Fabric mod above.
    [[ ${#slugs[@]} -gt 0 ]] && slugs=("fabric-api" "${slugs[@]}")

    if [[ ${#slugs[@]} -eq 0 ]]; then
        bashio::log.info "No managed mods enabled."
        return 0
    fi

    # De-duplicate while preserving order.
    local -a uniq=()
    local s seen
    for s in "${slugs[@]}"; do
        seen=false
        if [[ ${#uniq[@]} -gt 0 ]]; then
            for u in "${uniq[@]}"; do [[ "${u}" == "${s}" ]] && seen=true && break; done
        fi
        [[ "${seen}" == false ]] && uniq+=("${s}")
    done

    bashio::log.info "Synchronising ${#uniq[@]} mod(s) for Minecraft ${MC_VERSION}..."
    for s in "${uniq[@]}"; do
        download_mod "${s}"
    done
}

# ---------------------------------------------------------------------------
# server.properties (regenerated from options on every start)
# ---------------------------------------------------------------------------
write_server_properties() {
    bashio::log.info "Writing server.properties..."
    {
        echo "# Generated by the Home Assistant Fabric Server add-on — do not edit manually."
        echo "motd=$(opt motd)"
        echo "server-port=25565"
        echo "query.port=25565"
        echo "gamemode=$(opt gamemode)"
        echo "difficulty=$(opt difficulty)"
        echo "hardcore=$(opt hardcore)"
        echo "max-players=$(opt max_players)"
        echo "online-mode=$(opt online_mode)"
        echo "white-list=$(opt white_list)"
        echo "enforce-whitelist=$(opt white_list)"
        echo "pvp=$(opt pvp)"
        echo "allow-nether=$(opt allow_nether)"
        echo "allow-flight=$(opt allow_flight)"
        echo "spawn-protection=$(opt spawn_protection)"
        echo "view-distance=$(opt view_distance)"
        echo "simulation-distance=$(opt simulation_distance)"
        echo "level-name=$(opt level_name)"
        echo "level-seed=$(opt level_seed)"
        echo "level-type=$(opt level_type)"
        echo "enable-command-block=$(opt enable_command_block)"
        echo "op-permission-level=$(opt op_permission_level)"
        echo "player-idle-timeout=$(opt player_idle_timeout)"
        echo "enable-rcon=false"
        echo "sync-chunk-writes=true"
    } > "${SERVER_DIR}/server.properties"
}

# ---------------------------------------------------------------------------
# Geyser config (Bedrock cross-play). Geyser-Fabric integrates with
# Floodgate-Fabric automatically when both run on the same server, so no
# manual key exchange is needed.
# ---------------------------------------------------------------------------
write_geyser_config() {
    [[ "$(opt geyser_enabled)" != "true" ]] && return 0

    local auth="online"
    [[ "$(opt floodgate_enabled)" == "true" ]] && auth="floodgate"

    local cfg_dir="${SERVER_DIR}/config/Geyser-Fabric"
    mkdir -p "${cfg_dir}"
    bashio::log.info "Writing Geyser configuration (auth-type: ${auth})..."
    cat > "${cfg_dir}/config.yml" <<YAML
# Generated by the Home Assistant Fabric Server add-on — do not edit manually.
bedrock:
  address: 0.0.0.0
  port: $(opt bedrock_port)
  clone-remote-port: false
  motd1: "$(opt geyser_motd)"
  motd2: "$(opt motd)"
  server-name: "$(opt geyser_motd)"
  compression-level: 6
  enable-proxy-protocol: false
remote:
  address: 127.0.0.1
  port: 25565
  auth-type: ${auth}
  allow-password-authentication: true
  use-proxy-protocol: false
passthrough-motd: false
passthrough-player-counts: true
max-players: $(opt max_players)
debug-mode: false
YAML
}

# ---------------------------------------------------------------------------
# ops.json — resolve usernames to UUIDs via the Mojang API (best effort)
# ---------------------------------------------------------------------------
apply_ops() {
    local level; level="$(opt op_permission_level)"
    local entries="[]"
    local name uuid
    while IFS= read -r name; do
        [[ -z "${name}" ]] && continue
        if ! uuid="$(resolve_uuid "${name}")"; then
            bashio::log.warning "Could not resolve UUID for op '${name}'; skipping."
            continue
        fi
        entries="$(echo "${entries}" | jq \
            --arg u "${uuid}" --arg n "${name}" --argjson l "${level}" \
            '. += [{"uuid":$u,"name":$n,"level":$l,"bypassesPlayerLimit":false}]')"
        bashio::log.info "Op: ${name} (${uuid})."
    done < <(jq -r '.ops[]?' "${OPTIONS}")

    echo "${entries}" | jq '.' > "${SERVER_DIR}/ops.json"
}

# ---------------------------------------------------------------------------
# whitelist.json — regenerate from the (already merged) whitelist option.
# Names are resolved to UUIDs via the Mojang API, mirroring apply_ops.
# Always written so that entries removed from the option/in-game are cleared.
# ---------------------------------------------------------------------------
apply_whitelist() {
    local entries="[]"
    local name uuid
    while IFS= read -r name; do
        [[ -z "${name}" ]] && continue
        if ! uuid="$(resolve_uuid "${name}")"; then
            bashio::log.warning "Could not resolve UUID for whitelisted player '${name}'; skipping."
            continue
        fi
        entries="$(echo "${entries}" | jq \
            --arg u "${uuid}" --arg n "${name}" \
            '. += [{"uuid":$u,"name":$n}]')"
        bashio::log.info "Whitelisted: ${name} (${uuid})."
    done < <(jq -r '.whitelist[]?' "${OPTIONS}")

    echo "${entries}" | jq '.' > "${SERVER_DIR}/whitelist.json"
}

# ---------------------------------------------------------------------------
# Two-way config sync (runtime ⇆ options)
#
# Players change the server at runtime with commands such as /op, /deop and
# /whitelist, which the server records in ops.json / whitelist.json. Because
# we regenerate those files from the options on every start, those changes
# would otherwise be lost. sync_runtime_config performs a three-way merge so
# that additions and removals made *either* in-game *or* in the Home Assistant
# UI are preserved, writes the merged result back to the options via the
# Supervisor API, and updates the local options file so the rest of this start
# regenerates from the merged set.
# ---------------------------------------------------------------------------

# Three-way set merge of a list option against the live server file.
#   $1  option key in options.json (a list of strings)
#   $2  baseline file recording the previously synced set
#   stdin: the live names, one per line
# Echoes the merged set as a JSON array and refreshes the baseline.
merge_list() {
    local key="$1" baseline="$2"
    local live opt base removed union merged

    live="$(sort -u | sed '/^[[:space:]]*$/d')"
    opt="$(jq -r --arg k "${key}" '.[$k][]? // empty' "${OPTIONS}" | sort -u | sed '/^[[:space:]]*$/d')"
    base=""
    [[ -f "${baseline}" ]] && base="$(sort -u "${baseline}" | sed '/^[[:space:]]*$/d')"

    # An entry counts as removed when it was in the baseline but is now gone
    # from either side (in-game or the options).
    removed="$( {
        comm -23 <(printf '%s\n' "${base}") <(printf '%s\n' "${live}")
        comm -23 <(printf '%s\n' "${base}") <(printf '%s\n' "${opt}")
    } | sort -u | sed '/^[[:space:]]*$/d' )"

    # result = (live ∪ options) − removed
    union="$(printf '%s\n%s\n' "${live}" "${opt}" | sort -u | sed '/^[[:space:]]*$/d')"
    merged="$(comm -23 <(printf '%s\n' "${union}") <(printf '%s\n' "${removed}"))"

    printf '%s\n' "${merged}" | sed '/^[[:space:]]*$/d' > "${baseline}"
    printf '%s\n' "${merged}" | sed '/^[[:space:]]*$/d' | jq -R . | jq -s .
}

# Persist a full options object back to the add-on configuration.
# POST /addons/self/options replaces the stored options, so the caller passes
# the complete (merged) options object. No-op without SUPERVISOR_TOKEN.
supervisor_save_options() {
    local options_json="$1"

    if [[ -z "${SUPERVISOR_TOKEN:-}" ]]; then
        bashio::log.warning "SUPERVISOR_TOKEN not set; cannot sync changes to the add-on options."
        return 0
    fi

    local payload
    payload="$(jq -nc --argjson o "${options_json}" '{options: $o}')" || return 0

    if curl -fsSL -X POST \
        -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "${payload}" \
        "${SUPERVISOR_API}/addons/self/options" >/dev/null 2>&1; then
        bashio::log.info "Synced runtime changes back to the add-on options."
    else
        bashio::log.warning "Failed to sync options via the Supervisor API."
    fi
}

sync_runtime_config() {
    local updated; updated="$(cat "${OPTIONS}")"
    local live merged

    # ── Operators (ops.json ⇆ ops) ──────────────────────────────────────────
    live=""
    [[ -f "${SERVER_DIR}/ops.json" ]] && \
        live="$(jq -r '.[].name? // empty' "${SERVER_DIR}/ops.json" 2>/dev/null || true)"
    merged="$(printf '%s\n' "${live}" | merge_list ops "${OPS_BASELINE}")"
    updated="$(printf '%s' "${updated}" | jq --argjson a "${merged}" '.ops = $a')"

    # ── Whitelist (whitelist.json ⇆ whitelist) ───────────────────────────────
    live=""
    [[ -f "${SERVER_DIR}/whitelist.json" ]] && \
        live="$(jq -r '.[].name? // empty' "${SERVER_DIR}/whitelist.json" 2>/dev/null || true)"
    merged="$(printf '%s\n' "${live}" | merge_list whitelist "${WHITELIST_BASELINE}")"
    updated="$(printf '%s' "${updated}" | jq --argjson a "${merged}" '.whitelist = $a')"

    # Only write when the merge actually changed something.
    if ! printf '%s' "${updated}" | jq -e --slurpfile cur "${OPTIONS}" '. == $cur[0]' >/dev/null 2>&1; then
        printf '%s\n' "${updated}" > "${OPTIONS}"
        supervisor_save_options "${updated}"
    fi
}

# ---------------------------------------------------------------------------
# Build the JVM argument list into the global JVM_ARGS array
# ---------------------------------------------------------------------------
JVM_ARGS=()
build_jvm_args() {
    JVM_ARGS=(
        "-Xms$(opt min_memory)"
        "-Xmx$(opt max_memory)"
        # Aikar's flags — well-tested G1GC tuning for Minecraft servers.
        -XX:+UseG1GC
        -XX:+ParallelRefProcEnabled
        -XX:MaxGCPauseMillis=200
        -XX:+UnlockExperimentalVMOptions
        -XX:+DisableExplicitGC
        -XX:+AlwaysPreTouch
        -XX:G1NewSizePercent=30
        -XX:G1MaxNewSizePercent=40
        -XX:G1HeapRegionSize=8M
        -XX:G1ReservePercent=20
        -XX:G1HeapWastePercent=5
        -XX:G1MixedGCCountTarget=4
        -XX:InitiatingHeapOccupancyPercent=15
        -XX:G1MixedGCLiveThresholdPercent=90
        -XX:G1RSetUpdatingPauseTimePercent=5
        -XX:SurvivorRatio=32
        -XX:+PerfDisableSharedMem
        -XX:MaxTenuringThreshold=1
        -Dusing.aikars.flags=https://mcflags.emc.gs
        -Daikars.new.flags=true
    )

    local extra; extra="$(opt java_args)"
    if [[ -n "${extra}" ]]; then
        local -a extra_arr
        read -ra extra_arr <<< "${extra}"
        JVM_ARGS+=("${extra_arr[@]}")
    fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    mkdir -p "${SERVER_DIR}"

    handle_eula
    resolve_versions
    download_server_jar
    sync_mods
    # Pull any in-game /op and /whitelist changes from the previous session
    # into the options before we regenerate the server files from them.
    sync_runtime_config
    write_server_properties
    write_geyser_config
    apply_ops
    apply_whitelist

    build_jvm_args

    bashio::log.info "Starting Fabric server..."
    cd "${SERVER_DIR}"
    exec "${JAVA_BIN}" "${JVM_ARGS[@]}" -jar "${LAUNCHER_JAR}" nogui
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi
