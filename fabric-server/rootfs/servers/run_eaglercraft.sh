#!/bin/bash
# EaglercraftX server — allows Minecraft to be played from a web browser.
# Requires common.sh to be sourced first.
#
# EaglercraftX is a community project (https://git.eaglercraft.rip/eaglercraft).
# This add-on cannot auto-download EaglercraftX server JARs because there is
# no official release API. You must obtain the JAR yourself:
#
#   1. Download the EaglercraftX BungeeCord or standalone server JAR from the
#      official EaglercraftX repository or trusted community mirrors.
#   2. Place the JAR at:  /share/mc_server/eaglercraft-server.jar
#   3. Start the add-on.
#
# NOTE: EaglercraftX servers target Minecraft 1.8.x protocols. Set
#       minecraft_version to "1.8.9" or the version your JAR expects.
#
# NOTE: EaglercraftX server JARs typically bundle their own web server for
#       browser clients on a configurable port separate from this dashboard.
#
# NOTE: Geyser, Floodgate, ViaVersion, optimization mods, and Extra Mods are
#       not managed for EaglercraftX — its mod/plugin ecosystem is separate
#       and version-specific to whichever JAR you supply.

EAGLERCRAFT_JAR="${EAGLERCRAFT_JAR:-${SERVER_DIR}/eaglercraft-server.jar}"

prepare_eaglercraft() {
    if [[ ! -f "${EAGLERCRAFT_JAR}" ]]; then
        bashio::log.fatal "EaglercraftX server JAR not found at ${EAGLERCRAFT_JAR}."
        bashio::log.fatal "Place the JAR there and restart the add-on."
        bashio::log.fatal "See the add-on documentation for details."
        return 1
    fi

    MC_VERSION="$(opt minecraft_version)"
    [[ -z "${MC_VERSION}" || "${MC_VERSION}" == "latest" ]] && MC_VERSION="1.8.9"

    bashio::log.info "Starting EaglercraftX server (JAR: ${EAGLERCRAFT_JAR})."

    SERVER_LAUNCH=("${JAVA_BIN}" "${JVM_ARGS[@]}" -jar "${EAGLERCRAFT_JAR}" nogui)
    SERVER_WORKDIR="${SERVER_DIR}"
}
