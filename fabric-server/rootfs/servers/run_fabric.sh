#!/bin/bash
# Fabric server — version resolution, mod sync, Geyser config, server launch.
# Requires common.sh to be sourced first.
# All paths use ${SERVER_DIR} / ${DATA_DIR} directly so that test overrides work.

FABRIC_META="${FABRIC_META:-https://meta.fabricmc.net/v2}"

LOADER_VERSION=""
INSTALLER_VERSION=""

# ---------------------------------------------------------------------------
# Version resolution
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
        bashio::log.fatal "Could not resolve Fabric versions."
        return 1
    fi

    bashio::log.info "Minecraft ${MC_VERSION} · Fabric loader ${LOADER_VERSION} · installer ${INSTALLER_VERSION}"
}

# ---------------------------------------------------------------------------
# Download Fabric launcher jar
# ---------------------------------------------------------------------------
download_server_jar() {
    local launcher_jar="${SERVER_DIR}/fabric-server-launch.jar"
    local version_marker="${DATA_DIR}/.fabric_version"
    local desired="${MC_VERSION}-${LOADER_VERSION}-${INSTALLER_VERSION}"

    if [[ -f "${launcher_jar}" && "$(cat "${version_marker}" 2>/dev/null)" == "${desired}" ]]; then
        bashio::log.info "Fabric server launcher already up to date."
        return 0
    fi

    local url="${FABRIC_META}/versions/loader/${MC_VERSION}/${LOADER_VERSION}/${INSTALLER_VERSION}/server/jar"
    bashio::log.info "Downloading Fabric server launcher..."
    if ! curl -fsSL -o "${launcher_jar}.tmp" "${url}"; then
        bashio::log.fatal "Failed to download Fabric server launcher from ${url}"
        rm -f "${launcher_jar}.tmp"
        return 1
    fi
    mv "${launcher_jar}.tmp" "${launcher_jar}"
    echo "${desired}" > "${version_marker}"
}

# ---------------------------------------------------------------------------
# Sync managed mods — backward-compat wrapper around the shared
# sync_server_mods() in common.sh (used directly by Fabric tests).
# ---------------------------------------------------------------------------
sync_mods() {
    sync_server_mods "fabric" "${SERVER_DIR}/mods"
}

# ---------------------------------------------------------------------------
# Entry point called by run.sh
# ---------------------------------------------------------------------------
prepare_fabric() {
    # Expose globals so tests that check MODS_DIR / MANAGED_FILE / LAUNCHER_JAR
    # / VERSION_MARKER still work after SERVER_DIR / DATA_DIR are overridden.
    MODS_DIR="${SERVER_DIR}/mods"
    MANAGED_FILE="${DATA_DIR}/.managed_mods"
    LAUNCHER_JAR="${SERVER_DIR}/fabric-server-launch.jar"
    VERSION_MARKER="${DATA_DIR}/.fabric_version"

    resolve_versions
    download_server_jar
    sync_mods
    write_geyser_config "fabric"

    SERVER_LAUNCH=("${JAVA_BIN}" "${JVM_ARGS[@]}" -jar "${LAUNCHER_JAR}" nogui)
    SERVER_WORKDIR="${SERVER_DIR}"
}
