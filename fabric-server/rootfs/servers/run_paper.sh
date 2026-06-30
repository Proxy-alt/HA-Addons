#!/bin/bash
# Paper server — downloads from the PaperMC API.
# Paper is a high-performance Spigot fork. Plugins go in SERVER_DIR/plugins/.
# Requires common.sh to be sourced first.
#
# Geyser, Floodgate, and ViaVersion/ViaBackwards/ViaRewind are managed
# automatically as Bukkit plugins (fetched from Modrinth). Fabric-only
# optimization mods (Lithium, FerriteCore, Krypton, C2ME, ServerCore) are
# skipped — Paper has its own built-in performance work. Extra Mods slugs
# are also tried as plugins against the paper/spigot loader.

PAPER_API="${PAPER_API:-https://api.papermc.io/v2}"

# ---------------------------------------------------------------------------
# Download the latest Paper build for the configured Minecraft version.
# ---------------------------------------------------------------------------
download_paper_jar() {
    local type_dir="${DATA_DIR}/paper"
    mkdir -p "${type_dir}"

    MC_VERSION="$(opt minecraft_version)"
    if [[ -z "${MC_VERSION}" || "${MC_VERSION}" == "latest" ]]; then
        MC_VERSION="$(curl -fsSL "${PAPER_API}/projects/paper" 2>/dev/null \
            | jq -r '.versions[-1] // empty')"
    fi
    [[ -z "${MC_VERSION}" ]] && { bashio::log.fatal "Could not determine Paper Minecraft version."; return 1; }

    bashio::log.info "Fetching latest Paper build for ${MC_VERSION}..."
    local builds_json
    builds_json="$(curl -fsSL "${PAPER_API}/projects/paper/versions/${MC_VERSION}/builds" 2>/dev/null)" || {
        bashio::log.fatal "Failed to fetch Paper builds for ${MC_VERSION}."
        return 1
    }

    local build_num
    build_num="$(echo "${builds_json}" | jq -r '[.builds[] | select(.channel == "default")] | last | .build // .builds[-1] // empty')"
    # Fallback: just take the last build regardless of channel
    if [[ -z "${build_num}" ]]; then
        build_num="$(echo "${builds_json}" | jq -r '.builds[-1].build // empty')"
    fi
    [[ -z "${build_num}" ]] && { bashio::log.fatal "No Paper build found for ${MC_VERSION}."; return 1; }

    local marker="${type_dir}/.paper_version"
    local jar="${type_dir}/paper.jar"
    local desired="${MC_VERSION}-${build_num}"
    if [[ -f "${jar}" && "$(cat "${marker}" 2>/dev/null)" == "${desired}" ]]; then
        bashio::log.info "Paper ${desired} already up to date."
        return 0
    fi

    local filename="paper-${MC_VERSION}-${build_num}.jar"
    local url="${PAPER_API}/projects/paper/versions/${MC_VERSION}/builds/${build_num}/downloads/${filename}"
    bashio::log.info "Downloading Paper ${desired}..."
    if ! curl -fsSL -o "${jar}.tmp" "${url}"; then
        bashio::log.fatal "Failed to download Paper from ${url}"
        rm -f "${jar}.tmp"
        return 1
    fi
    mv "${jar}.tmp" "${jar}"
    echo "${desired}" > "${marker}"
    bashio::log.info "Paper ${desired} ready."
}

prepare_paper() {
    download_paper_jar

    local jar="${DATA_DIR}/paper/paper.jar"
    # Accept Paper's EULA automatically (Minecraft EULA already confirmed)
    mkdir -p "${SERVER_DIR}/plugins"
    echo "eula=true" > "${SERVER_DIR}/eula.txt"

    sync_server_mods "paper" "${SERVER_DIR}/plugins"
    write_geyser_config "paper"

    SERVER_LAUNCH=("${JAVA_BIN}" "${JVM_ARGS[@]}" -jar "${jar}" nogui)
    SERVER_WORKDIR="${SERVER_DIR}"
}
