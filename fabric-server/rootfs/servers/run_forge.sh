#!/bin/bash
# Forge server — downloads the Forge installer and runs it, then launches.
# Requires common.sh to be sourced first.
#
# NOTE: Requires Java 17+ for Minecraft 1.17+, Java 21 for 1.21+.
#       The forge_version option accepts "latest", "recommended", or a specific
#       Forge build number (e.g. "54.1.0"). Use "recommended" for stable builds.
#
# NOTE: Mods go in SERVER_DIR/mods/ — Forge's mod loading is separate from Fabric.
#
# Geyser and ViaForge (the Forge port of ViaVersion) are managed automatically
# from Modrinth when enabled. ViaBackwards/ViaRewind are attempted too, but
# Forge builds of those mods may not exist for every Minecraft version — a
# missing build is skipped with a warning. Fabric-only optimization mods
# (Lithium, FerriteCore, Krypton, C2ME, ServerCore) have no Forge equivalent.

FORGE_PROMOTIONS="${FORGE_PROMOTIONS:-https://files.minecraftforge.net/net/minecraftforge/forge/promotions_slim.json}"
FORGE_MAVEN="${FORGE_MAVEN:-https://maven.minecraftforge.net/net/minecraftforge/forge}"

resolve_forge_version() {
    local mc_ver="$1" pref; pref="$(opt forge_version)"
    if [[ -z "${pref}" || "${pref}" == "latest" ]]; then
        pref="recommended"
    fi

    bashio::log.info "Fetching Forge promotions..."
    local promos
    promos="$(curl -fsSL "${FORGE_PROMOTIONS}" 2>/dev/null)" || {
        bashio::log.fatal "Could not fetch Forge promotions."
        return 1
    }

    local forge_ver
    if [[ "${pref}" == "recommended" ]]; then
        forge_ver="$(echo "${promos}" | jq -r --arg mc "${mc_ver}" '.promos[$mc+"-recommended"] // .promos[$mc+"-latest"] // empty')"
    else
        forge_ver="${pref}"
    fi
    [[ -z "${forge_ver}" ]] && { bashio::log.fatal "No Forge build found for Minecraft ${mc_ver}."; return 1; }

    echo "${forge_ver}"
}

install_forge() {
    local type_dir="${DATA_DIR}/forge"
    mkdir -p "${type_dir}"

    MC_VERSION="$(opt minecraft_version)"
    if [[ -z "${MC_VERSION}" || "${MC_VERSION}" == "latest" ]]; then
        bashio::log.fatal "Forge requires a specific minecraft_version (e.g. '1.21.4'). 'latest' is not supported."
        return 1
    fi

    local forge_ver
    forge_ver="$(resolve_forge_version "${MC_VERSION}")"
    local combined="${MC_VERSION}-${forge_ver}"

    local marker="${type_dir}/.forge_version"
    if [[ "$(cat "${marker}" 2>/dev/null)" == "${combined}" && -f "${SERVER_DIR}/libraries" || \
          "$(cat "${marker}" 2>/dev/null)" == "${combined}" && -f "${SERVER_DIR}/run.sh" ]]; then
        bashio::log.info "Forge ${combined} already installed."
        return 0
    fi

    local installer="${type_dir}/forge-installer.jar"
    local url="${FORGE_MAVEN}/${combined}/forge-${combined}-installer.jar"
    bashio::log.info "Downloading Forge installer for ${combined}..."
    if ! curl -fsSL -o "${installer}" "${url}"; then
        bashio::log.fatal "Failed to download Forge installer from ${url}"
        return 1
    fi

    bashio::log.info "Running Forge installer (this may take several minutes)..."
    pushd "${SERVER_DIR}" >/dev/null
    if ! "${JAVA_BIN}" -jar "${installer}" --installServer 2>&1; then
        bashio::log.fatal "Forge installer failed."
        popd >/dev/null
        return 1
    fi
    popd >/dev/null

    echo "${combined}" > "${marker}"
    bashio::log.info "Forge ${combined} installed."
}

prepare_forge() {
    install_forge

    mkdir -p "${SERVER_DIR}/mods"
    sync_server_mods "forge" "${SERVER_DIR}/mods"
    write_geyser_config "forge"

    local combined="${MC_VERSION}-$(opt forge_version)"
    # 1.17+: installer generates run.sh; use it. Pre-1.17: use the server jar directly.
    if [[ -f "${SERVER_DIR}/run.sh" ]]; then
        # Inject JVM args via environment variable that the generated run.sh honours
        export JAVA_OPTS="${JVM_ARGS[*]}"
        SERVER_LAUNCH=("${SERVER_DIR}/run.sh" nogui)
    elif ls "${SERVER_DIR}"/forge-*-server.jar 2>/dev/null | head -1 | grep -q .; then
        local forge_jar
        forge_jar="$(ls "${SERVER_DIR}"/forge-*-server.jar 2>/dev/null | head -1)"
        SERVER_LAUNCH=("${JAVA_BIN}" "${JVM_ARGS[@]}" -jar "${forge_jar}" nogui)
    else
        bashio::log.fatal "Could not find Forge server jar or run.sh after installation."
        return 1
    fi

    SERVER_WORKDIR="${SERVER_DIR}"
}
