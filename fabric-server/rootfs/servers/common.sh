#!/bin/bash
# Shared helpers used by every server-type script.
# Source this file first; it defines globals and functions but does not exec anything.
# shellcheck disable=SC1091

source "${BASHIO_LIB:-/usr/lib/bashio/bashio.sh}"

# ---------------------------------------------------------------------------
# Paths / endpoints (overridable for tests and alternate server types)
# ---------------------------------------------------------------------------
OPTIONS="${OPTIONS:-/data/options.json}"
SERVER_DIR="${SERVER_DIR:-/share/mc_server}"
ADDON_CONFIG_DIR="${ADDON_CONFIG_DIR:-/config}"
DATA_DIR="${DATA_DIR:-/data}"
MOJANG_API="${MOJANG_API:-https://api.mojang.com}"
MODRINTH_API="${MODRINTH_API:-https://api.modrinth.com/v2}"
SUPERVISOR_API="${SUPERVISOR_API:-http://supervisor}"
JAVA_BIN="${JAVA_BIN:-java}"

OPS_BASELINE="${DATA_DIR}/.synced_ops"
WHITELIST_BASELINE="${DATA_DIR}/.synced_whitelist"

# Set by the server-type prepare function
MC_VERSION=""

# Set by sync_server_mods for test/caller visibility
MODS_DIR=""
MANAGED_FILE=""

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

opt() { jq -r --arg k "$1" '.[$k] | select(. != null)' "${OPTIONS}"; }

resolve_uuid() {
    local name="$1" prof id
    prof="$(curl -fsSL "${MOJANG_API}/users/profiles/minecraft/${name}" 2>/dev/null || true)"
    id="$(echo "${prof}" | jq -r '.id // empty' 2>/dev/null || true)"
    [[ -z "${id}" ]] && return 1
    printf '%s-%s-%s-%s-%s' "${id:0:8}" "${id:8:4}" "${id:12:4}" "${id:16:4}" "${id:20:12}"
}

# Return the URL-encoded JSON loader array for the Modrinth /version query.
# Using broad loader lists so plugins listed under "spigot" are returned for "paper" queries.
_modrinth_loaders_param() {
    case "$1" in
        fabric) echo '%5B%22fabric%22%5D' ;;
        forge)  echo '%5B%22forge%22%5D' ;;
        purpur) echo '%5B%22purpur%22%2C%22paper%22%2C%22spigot%22%5D' ;;
        paper)  echo '%5B%22paper%22%2C%22spigot%22%2C%22bukkit%22%5D' ;;
        *)      printf '%%5B%%22%s%%22%%5D' "$1" ;;
    esac
}

# ---------------------------------------------------------------------------
# Modrinth mod/plugin download
#
# Picks the newest version matching the loader and MC version. Falls back to
# any version for the loader if no MC-version-specific build is found.
# ---------------------------------------------------------------------------
download_modrinth_mod() {
    local slug="$1" loader="$2" dest_dir="$3" managed_file="$4"
    local loaders_param; loaders_param="$(_modrinth_loaders_param "${loader}")"

    local json url
    url="${MODRINTH_API}/project/${slug}/version?loaders=${loaders_param}&game_versions=%5B%22${MC_VERSION}%22%5D"
    json="$(curl -fsSL "${url}" 2>/dev/null || true)"

    # Retry without game_version constraint (some mods omit per-MC metadata)
    if [[ -z "${json}" || "$(echo "${json}" | jq 'length' 2>/dev/null || echo 0)" == "0" ]]; then
        url="${MODRINTH_API}/project/${slug}/version?loaders=${loaders_param}"
        json="$(curl -fsSL "${url}" 2>/dev/null || true)"
    fi

    if [[ -z "${json}" || "$(echo "${json}" | jq 'length' 2>/dev/null || echo 0)" == "0" ]]; then
        bashio::log.warning "No '${slug}' build for loader=${loader} / MC=${MC_VERSION}; skipping."
        return 0
    fi

    local picker='sort_by(.date_published) | reverse | .[0].files | (map(select(.primary)) + .)[0]'
    local file_url file_name
    file_url="$(echo "${json}" | jq -r "${picker}.url // empty")"
    file_name="$(echo "${json}" | jq -r "${picker}.filename // empty")"

    if [[ -z "${file_url}" || -z "${file_name}" ]]; then
        bashio::log.warning "Could not determine a download for '${slug}'; skipping."
        return 0
    fi

    if curl -fsSL -o "${dest_dir}/${file_name}" "${file_url}"; then
        echo "${file_name}" >> "${managed_file}"
        bashio::log.info "Installed '${slug}' (${file_name})."
    else
        bashio::log.warning "Failed to download '${slug}'; skipping."
        rm -f "${dest_dir}/${file_name}"
    fi
}

# ---------------------------------------------------------------------------
# Sync managed mods / plugins for any server type.
#
# Usage: sync_server_mods <loader> <dest_dir>
#   loader   — fabric | forge | paper | purpur (controls Modrinth query + slug selection)
#   dest_dir — mods/ for mod loaders, plugins/ for Bukkit-compatible servers
#
# Sets globals MODS_DIR and MANAGED_FILE for test/caller visibility.
# ---------------------------------------------------------------------------
sync_server_mods() {
    local loader="$1" dest_dir="$2"

    # Per-loader managed-file; Fabric keeps the legacy name for test compat.
    local managed_file
    case "${loader}" in
        fabric) managed_file="${DATA_DIR}/.managed_mods" ;;
        *)      managed_file="${DATA_DIR}/.managed_mods_${loader}" ;;
    esac

    MODS_DIR="${dest_dir}"
    MANAGED_FILE="${managed_file}"
    mkdir -p "${dest_dir}"

    # Remove previously installed managed mods/plugins
    if [[ -f "${managed_file}" ]]; then
        while IFS= read -r f; do
            [[ -n "${f}" ]] && rm -f "${dest_dir}/${f}"
        done < "${managed_file}"
    fi
    : > "${managed_file}"

    local -a slugs=()

    # ── Geyser + Floodgate ──────────────────────────────────────────────────
    # Available for fabric, paper, purpur, and forge via Modrinth.
    # BDS is native Bedrock and does not need Geyser.
    [[ "$(opt geyser_enabled)" == "true" ]]    && slugs+=("geyser")
    [[ "$(opt floodgate_enabled)" == "true" ]] && slugs+=("floodgate")

    # ── Via* protocol compatibility ─────────────────────────────────────────
    # ViaVersion base slug differs by platform:
    #   fabric → viafabric  (the Fabric port; bundles ViaVersion)
    #   forge  → viaforge   (the Forge port)
    #   paper/purpur/spigot → viaversion  (the original Spigot plugin)
    # ViaBackwards and ViaRewind share the same Modrinth slugs across platforms;
    # Modrinth returns the correct build for the queried loader.
    local viaversion; viaversion="$(opt viaversion_enabled)"
    local viabackwards; viabackwards="$(opt viabackwards_enabled)"
    local viarewind; viarewind="$(opt viarewind_enabled)"

    if [[ "${viaversion}" == "true" ]]; then
        case "${loader}" in
            fabric) slugs+=("viafabric") ;;
            forge)  slugs+=("viaforge") ;;
            *)      slugs+=("viaversion") ;;
        esac

        if [[ "${viabackwards}" == "true" ]]; then
            slugs+=("viabackwards")
            [[ "${viarewind}" == "true" ]] && slugs+=("viarewind")
        elif [[ "${viarewind}" == "true" ]]; then
            bashio::log.fatal "ViaRewind requires ViaBackwards to be enabled."
        fi
    elif [[ "${viabackwards}" == "true" || "${viarewind}" == "true" ]]; then
        bashio::log.fatal "ViaBackwards and ViaRewind require ViaVersion to be enabled."
    fi

    # ── Optimization mods (Fabric-only) ─────────────────────────────────────
    # lithium, ferritecore, krypton, c2me, servercore are Fabric mods with no
    # equivalent on other loaders. They are silently skipped with a note.
    if [[ "${loader}" == "fabric" ]]; then
        [[ "$(opt mod_lithium)" == "true" ]]     && slugs+=("lithium")
        [[ "$(opt mod_ferritecore)" == "true" ]] && slugs+=("ferrite-core")
        [[ "$(opt mod_krypton)" == "true" ]]     && slugs+=("krypton")
        [[ "$(opt mod_c2me)" == "true" ]]        && slugs+=("c2me-fabric")
        [[ "$(opt mod_servercore)" == "true" ]]  && slugs+=("servercore")
    else
        local -a fabric_only=()
        [[ "$(opt mod_lithium)" == "true" ]]     && fabric_only+=("lithium")
        [[ "$(opt mod_ferritecore)" == "true" ]] && fabric_only+=("ferritecore")
        [[ "$(opt mod_krypton)" == "true" ]]     && fabric_only+=("krypton")
        [[ "$(opt mod_c2me)" == "true" ]]        && fabric_only+=("c2me")
        [[ "$(opt mod_servercore)" == "true" ]]  && fabric_only+=("servercore")
        if [[ ${#fabric_only[@]} -gt 0 ]]; then
            bashio::log.warning \
                "Optimization mods (${fabric_only[*]}) are Fabric-only and will not be installed for ${loader}."
        fi
    fi

    # ── Extra mods/plugins ───────────────────────────────────────────────────
    # extra_mods slugs are tried against the active loader; Modrinth returns
    # nothing if the slug has no build for that loader (skipped with a warning).
    while IFS= read -r s; do
        [[ -n "${s}" ]] && slugs+=("${s}")
    done < <(jq -r '.extra_mods[]?' "${OPTIONS}")

    # fabric-api is required by every Fabric mod above; add it automatically.
    if [[ "${loader}" == "fabric" && ${#slugs[@]} -gt 0 ]]; then
        slugs=("fabric-api" "${slugs[@]}")
    fi

    if [[ ${#slugs[@]} -eq 0 ]]; then
        bashio::log.info "No managed mods/plugins enabled for ${loader}."
        return 0
    fi

    # De-duplicate while preserving order
    local -a uniq=()
    local s seen
    for s in "${slugs[@]}"; do
        seen=false
        if [[ ${#uniq[@]} -gt 0 ]]; then
            for u in "${uniq[@]}"; do [[ "${u}" == "${s}" ]] && seen=true && break; done
        fi
        [[ "${seen}" == false ]] && uniq+=("${s}")
    done

    bashio::log.info "Syncing ${#uniq[@]} mod(s)/plugin(s) for loader=${loader}, MC=${MC_VERSION}..."
    for s in "${uniq[@]}"; do
        download_modrinth_mod "${s}" "${loader}" "${dest_dir}" "${managed_file}"
    done
}

# ---------------------------------------------------------------------------
# Geyser config — loader-aware config path.
#
# Usage: write_geyser_config <loader>
#   fabric/forge  → config/<PlatformName>/config.yml
#   paper/purpur  → plugins/Geyser-Spigot/config.yml
# ---------------------------------------------------------------------------
write_geyser_config() {
    [[ "$(opt geyser_enabled)" != "true" ]] && return 0

    local loader="${1:-fabric}"
    local auth="online"
    [[ "$(opt floodgate_enabled)" == "true" ]] && auth="floodgate"

    local cfg_dir
    case "${loader}" in
        fabric) cfg_dir="${SERVER_DIR}/config/Geyser-Fabric" ;;
        forge)  cfg_dir="${SERVER_DIR}/config/Geyser-Forge" ;;
        *)      cfg_dir="${SERVER_DIR}/plugins/Geyser-Spigot" ;;
    esac
    mkdir -p "${cfg_dir}"
    bashio::log.info "Writing Geyser config for ${loader} (auth-type: ${auth})..."

    cat > "${cfg_dir}/config.yml" <<YAML
# Generated by the Home Assistant Minecraft Server add-on — do not edit manually.
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
# Config-file symlinks
# ---------------------------------------------------------------------------
link_config_files() {
    mkdir -p "${ADDON_CONFIG_DIR}"

    for rel in eula.txt server.properties ops.json whitelist.json; do
        local dst="${SERVER_DIR}/${rel}"
        if [[ -f "${dst}" && ! -L "${dst}" ]]; then
            mv "${dst}" "${ADDON_CONFIG_DIR}/${rel}"
        fi
        ln -sfn "${ADDON_CONFIG_DIR}/${rel}" "${dst}"
    done

    local config_src="${ADDON_CONFIG_DIR}/config"
    local config_dst="${SERVER_DIR}/config"
    mkdir -p "${config_src}"
    if [[ -d "${config_dst}" && ! -L "${config_dst}" ]]; then
        cp -a "${config_dst}/." "${config_src}/"
        rm -rf "${config_dst}"
    fi
    ln -sfn "${config_src}" "${config_dst}"
}

# ---------------------------------------------------------------------------
# EULA
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
# server.properties
# ---------------------------------------------------------------------------
write_server_properties() {
    bashio::log.info "Writing server.properties..."
    {
        echo "# Generated by the Home Assistant Minecraft Server add-on — do not edit manually."
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
# ops.json
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
# whitelist.json
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
# World directory
# ---------------------------------------------------------------------------
prepare_world() {
    local level_name; level_name="$(opt level_name)"
    [[ -z "${level_name}" ]] && level_name="world"

    local target="${SERVER_DIR}/${level_name}"
    local old_addon_world="${ADDON_CONFIG_DIR}/${level_name}"

    [[ -L "${target}" ]] && rm -f "${target}"

    if [[ -d "${old_addon_world}" && ! -L "${old_addon_world}" ]]; then
        if [[ ! -e "${target}" ]]; then
            bashio::log.info "Migrating world '${level_name}' from add-on config to share..."
            mv "${old_addon_world}" "${target}"
        else
            bashio::log.warning \
                "World exists in both ${old_addon_world} and ${target}; using share copy."
        fi
    fi

    mkdir -p "${target}"
    bashio::log.info "World '${level_name}' stored in share."
}

# ---------------------------------------------------------------------------
# Three-way list merge for ops / whitelist
# ---------------------------------------------------------------------------
merge_list() {
    local key="$1" baseline="$2"
    local live opt base removed union merged

    live="$(sort -u | sed '/^[[:space:]]*$/d')"
    opt="$(jq -r --arg k "${key}" '.[$k][]? // empty' "${OPTIONS}" | sort -u | sed '/^[[:space:]]*$/d')"
    base=""
    [[ -f "${baseline}" ]] && base="$(sort -u "${baseline}" | sed '/^[[:space:]]*$/d')"

    removed="$( {
        comm -23 <(printf '%s\n' "${base}") <(printf '%s\n' "${live}")
        comm -23 <(printf '%s\n' "${base}") <(printf '%s\n' "${opt}")
    } | sort -u | sed '/^[[:space:]]*$/d' )"

    union="$(printf '%s\n%s\n' "${live}" "${opt}" | sort -u | sed '/^[[:space:]]*$/d')"
    merged="$(comm -23 <(printf '%s\n' "${union}") <(printf '%s\n' "${removed}"))"

    printf '%s\n' "${merged}" | sed '/^[[:space:]]*$/d' > "${baseline}"
    printf '%s\n' "${merged}" | sed '/^[[:space:]]*$/d' | jq -R . | jq -s .
}

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

    live=""
    [[ -f "${SERVER_DIR}/ops.json" ]] && \
        live="$(jq -r '.[].name? // empty' "${SERVER_DIR}/ops.json" 2>/dev/null || true)"
    merged="$(printf '%s\n' "${live}" | merge_list ops "${OPS_BASELINE}")"
    updated="$(printf '%s' "${updated}" | jq --argjson a "${merged}" '.ops = $a')"

    live=""
    [[ -f "${SERVER_DIR}/whitelist.json" ]] && \
        live="$(jq -r '.[].name? // empty' "${SERVER_DIR}/whitelist.json" 2>/dev/null || true)"
    merged="$(printf '%s\n' "${live}" | merge_list whitelist "${WHITELIST_BASELINE}")"
    updated="$(printf '%s' "${updated}" | jq --argjson a "${merged}" '.whitelist = $a')"

    if ! printf '%s' "${updated}" | jq -e --slurpfile cur "${OPTIONS}" '. == $cur[0]' >/dev/null 2>&1; then
        printf '%s\n' "${updated}" > "${OPTIONS}"
        supervisor_save_options "${updated}"
    fi
}

# ---------------------------------------------------------------------------
# JVM argument list (Java servers only)
# ---------------------------------------------------------------------------
JVM_ARGS=()
build_jvm_args() {
    JVM_ARGS=(
        "-Xms$(opt min_memory)"
        "-Xmx$(opt max_memory)"
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
