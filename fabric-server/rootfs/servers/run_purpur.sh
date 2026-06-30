#!/bin/bash
# Purpur server — downloads from purpurmc.org.
# Purpur is a Paper fork with extra configuration options and patches.
# Plugins go in SERVER_DIR/plugins/.
# Requires common.sh to be sourced first.
#
# Geyser, Floodgate, and ViaVersion/ViaBackwards/ViaRewind are managed
# automatically as Bukkit plugins (fetched from Modrinth, same as Paper since
# Purpur is plugin-compatible). Fabric-only optimization mods have no Purpur
# equivalent and are skipped.

PURPUR_API="${PURPUR_API:-https://api.purpurmc.org/v2}"

download_purpur_jar() {
    local type_dir="${DATA_DIR}/purpur"
    mkdir -p "${type_dir}"

    MC_VERSION="$(opt minecraft_version)"
    if [[ -z "${MC_VERSION}" || "${MC_VERSION}" == "latest" ]]; then
        MC_VERSION="$(curl -fsSL "${PURPUR_API}/purpur" 2>/dev/null \
            | jq -r '.versions[-1] // empty')"
    fi
    [[ -z "${MC_VERSION}" ]] && { bashio::log.fatal "Could not determine Purpur Minecraft version."; return 1; }

    bashio::log.info "Fetching latest Purpur build for ${MC_VERSION}..."
    local build_info
    build_info="$(curl -fsSL "${PURPUR_API}/purpur/${MC_VERSION}/latest" 2>/dev/null)" || {
        bashio::log.fatal "Failed to fetch Purpur build info for ${MC_VERSION}."
        return 1
    }

    local build_num
    build_num="$(echo "${build_info}" | jq -r '.build // empty')"
    [[ -z "${build_num}" ]] && { bashio::log.fatal "No Purpur build found for ${MC_VERSION}."; return 1; }

    local marker="${type_dir}/.purpur_version"
    local jar="${type_dir}/purpur.jar"
    local desired="${MC_VERSION}-${build_num}"
    if [[ -f "${jar}" && "$(cat "${marker}" 2>/dev/null)" == "${desired}" ]]; then
        bashio::log.info "Purpur ${desired} already up to date."
        return 0
    fi

    local url="${PURPUR_API}/purpur/${MC_VERSION}/latest/download"
    bashio::log.info "Downloading Purpur ${desired}..."
    if ! curl -fsSL -o "${jar}.tmp" "${url}"; then
        bashio::log.fatal "Failed to download Purpur from ${url}"
        rm -f "${jar}.tmp"
        return 1
    fi
    mv "${jar}.tmp" "${jar}"
    echo "${desired}" > "${marker}"
    bashio::log.info "Purpur ${desired} ready."
}

prepare_purpur() {
    download_purpur_jar

    local jar="${DATA_DIR}/purpur/purpur.jar"
    mkdir -p "${SERVER_DIR}/plugins"
    echo "eula=true" > "${SERVER_DIR}/eula.txt"

    sync_server_mods "purpur" "${SERVER_DIR}/plugins"
    write_geyser_config "paper"

    SERVER_LAUNCH=("${JAVA_BIN}" "${JVM_ARGS[@]}" -jar "${jar}" nogui)
    SERVER_WORKDIR="${SERVER_DIR}"
}
