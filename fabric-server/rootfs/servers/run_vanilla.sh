#!/bin/bash
# Vanilla server — downloads the official Mojang server jar.
# Requires common.sh to be sourced first.
#
# NOTE: Vanilla has no mod/plugin loader. Geyser, Floodgate, ViaVersion, the
#       optimization mods, and Extra Mods are all unsupported on this server
#       type and are silently ignored even if enabled in the UI.

MOJANG_MANIFEST="${MOJANG_MANIFEST:-https://launchermeta.mojang.com/mc/game/version_manifest_v2.json}"

# ---------------------------------------------------------------------------
# Download the vanilla server jar for the configured Minecraft version.
# ---------------------------------------------------------------------------
download_vanilla_jar() {
    local type_dir="${DATA_DIR}/vanilla"
    mkdir -p "${type_dir}"

    local target_version; target_version="$(opt minecraft_version)"

    bashio::log.info "Fetching Minecraft version manifest..."
    local manifest
    manifest="$(curl -fsSL "${MOJANG_MANIFEST}" 2>/dev/null)" || {
        bashio::log.fatal "Could not fetch Minecraft version manifest."
        return 1
    }

    if [[ -z "${target_version}" || "${target_version}" == "latest" ]]; then
        target_version="$(echo "${manifest}" | jq -r '.latest.release // empty')"
    fi
    [[ -z "${target_version}" ]] && { bashio::log.fatal "Could not determine target Minecraft version."; return 1; }
    MC_VERSION="${target_version}"

    local marker="${type_dir}/.vanilla_version"
    local jar="${type_dir}/server.jar"
    if [[ -f "${jar}" && "$(cat "${marker}" 2>/dev/null)" == "${MC_VERSION}" ]]; then
        bashio::log.info "Vanilla server jar already up to date (${MC_VERSION})."
        return 0
    fi

    local version_url
    version_url="$(echo "${manifest}" | jq -r --arg v "${MC_VERSION}" '.versions[] | select(.id == $v) | .url // empty')"
    if [[ -z "${version_url}" ]]; then
        bashio::log.fatal "Minecraft version '${MC_VERSION}' not found in the manifest."
        return 1
    fi

    local server_url
    server_url="$(curl -fsSL "${version_url}" 2>/dev/null | jq -r '.downloads.server.url // empty')"
    if [[ -z "${server_url}" ]]; then
        bashio::log.fatal "No server download available for Minecraft ${MC_VERSION}."
        return 1
    fi

    bashio::log.info "Downloading Vanilla server jar for ${MC_VERSION}..."
    if ! curl -fsSL -o "${jar}.tmp" "${server_url}"; then
        bashio::log.fatal "Failed to download Vanilla server jar."
        rm -f "${jar}.tmp"
        return 1
    fi
    mv "${jar}.tmp" "${jar}"
    echo "${MC_VERSION}" > "${marker}"
    bashio::log.info "Vanilla ${MC_VERSION} server jar ready."
}

prepare_vanilla() {
    download_vanilla_jar

    if [[ "$(opt geyser_enabled)" == "true" || "$(opt viaversion_enabled)" == "true" \
        || "$(opt mod_lithium)" == "true" || "$(opt mod_ferritecore)" == "true" \
        || "$(opt mod_krypton)" == "true" || "$(opt mod_c2me)" == "true" \
        || "$(opt mod_servercore)" == "true" \
        || "$(jq -e '(.extra_mods // []) | length > 0' "${OPTIONS}")" == "true" ]]; then
        bashio::log.warning \
            "Vanilla has no mod/plugin loader; Geyser/Via*/optimization mods/Extra Mods are ignored."
    fi

    local jar="${DATA_DIR}/vanilla/server.jar"
    SERVER_LAUNCH=("${JAVA_BIN}" "${JVM_ARGS[@]}" -jar "${jar}" nogui)
    SERVER_WORKDIR="${SERVER_DIR}"
}
