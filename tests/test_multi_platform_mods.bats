#!/usr/bin/env bats
# Tests for cross-platform mod/plugin sync (common.sh: sync_server_mods,
# download_modrinth_mod, write_geyser_config) across Paper/Purpur/Forge.

load helpers/common

setup() {
    setup_tmpdir
}

teardown() {
    teardown_tmpdir
}

use_curl_mock() {
    curl() { fabric_mock_curl "$@"; }
}

set_via_options() {
    jq --argjson v "$1" --argjson b "$2" --argjson r "$3" \
        '.viaversion_enabled = $v | .viabackwards_enabled = $b | .viarewind_enabled = $r' \
        "${OPTIONS}" > "${TEST_TMPDIR}/via_opts.json"
    OPTIONS="${TEST_TMPDIR}/via_opts.json"
}

# ---------------------------------------------------------------------------
# Paper
# ---------------------------------------------------------------------------

@test "sync_server_mods installs geyser/floodgate plugins for paper" {
    load_fabric_run "${FIXTURES_DIR}/options_fabric_defaults.json"
    use_curl_mock
    MC_VERSION="1.21.4"
    sync_server_mods "paper" "${SERVER_DIR}/plugins"
    [ "${MODS_DIR}" = "${SERVER_DIR}/plugins" ]
    grep -q '^geyser.jar$' "${MANAGED_FILE}"
    grep -q '^floodgate.jar$' "${MANAGED_FILE}"
    [ -f "${SERVER_DIR}/plugins/geyser.jar" ]
}

@test "sync_server_mods installs viaversion (not viafabric) for paper" {
    load_fabric_run "${FIXTURES_DIR}/options_fabric_defaults.json"
    set_via_options true true true
    use_curl_mock
    MC_VERSION="1.21.4"
    sync_server_mods "paper" "${SERVER_DIR}/plugins"
    grep -q '^viaversion.jar$' "${MANAGED_FILE}"
    grep -q '^viabackwards.jar$' "${MANAGED_FILE}"
    grep -q '^viarewind.jar$' "${MANAGED_FILE}"
    ! grep -q '^viafabric.jar$' "${MANAGED_FILE}"
}

@test "sync_server_mods skips fabric-only optimization mods for paper" {
    load_fabric_run "${FIXTURES_DIR}/options_fabric_defaults.json"
    use_curl_mock
    MC_VERSION="1.21.4"
    run sync_server_mods "paper" "${SERVER_DIR}/plugins"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"Fabric-only"* ]]
    ! grep -q '^lithium.jar$' "${MANAGED_FILE}"
    ! grep -q '^ferrite-core.jar$' "${MANAGED_FILE}"
    ! grep -q '^fabric-api.jar$' "${MANAGED_FILE}"
}

@test "sync_server_mods does not prefix fabric-api for paper" {
    load_fabric_run "${FIXTURES_DIR}/options_fabric_defaults.json"
    use_curl_mock
    MC_VERSION="1.21.4"
    sync_server_mods "paper" "${SERVER_DIR}/plugins"
    ! grep -q '^fabric-api.jar$' "${MANAGED_FILE}"
}

@test "sync_server_mods uses a separate managed file for paper than fabric" {
    load_fabric_run "${FIXTURES_DIR}/options_fabric_defaults.json"
    use_curl_mock
    MC_VERSION="1.21.4"
    sync_server_mods "paper" "${SERVER_DIR}/plugins"
    [[ "${MANAGED_FILE}" == *".managed_mods_paper" ]]
}

# ---------------------------------------------------------------------------
# Purpur (Paper-compatible loader queries)
# ---------------------------------------------------------------------------

@test "sync_server_mods installs viaversion for purpur" {
    load_fabric_run "${FIXTURES_DIR}/options_fabric_defaults.json"
    set_via_options true false false
    use_curl_mock
    MC_VERSION="1.21.4"
    sync_server_mods "purpur" "${SERVER_DIR}/plugins"
    grep -q '^viaversion.jar$' "${MANAGED_FILE}"
}

# ---------------------------------------------------------------------------
# Forge
# ---------------------------------------------------------------------------

@test "sync_server_mods installs viaforge (not viafabric/viaversion) for forge" {
    load_fabric_run "${FIXTURES_DIR}/options_fabric_defaults.json"
    set_via_options true false false
    use_curl_mock
    MC_VERSION="1.21.4"
    sync_server_mods "forge" "${SERVER_DIR}/mods"
    grep -q '^viaforge.jar$' "${MANAGED_FILE}"
    ! grep -q '^viafabric.jar$' "${MANAGED_FILE}"
    ! grep -q '^viaversion.jar$' "${MANAGED_FILE}"
}

@test "sync_server_mods installs geyser for forge" {
    load_fabric_run "${FIXTURES_DIR}/options_fabric_defaults.json"
    use_curl_mock
    MC_VERSION="1.21.4"
    sync_server_mods "forge" "${SERVER_DIR}/mods"
    grep -q '^geyser.jar$' "${MANAGED_FILE}"
}

@test "sync_server_mods skips fabric-only optimization mods for forge" {
    load_fabric_run "${FIXTURES_DIR}/options_fabric_defaults.json"
    use_curl_mock
    MC_VERSION="1.21.4"
    run sync_server_mods "forge" "${SERVER_DIR}/mods"
    [[ "${output}" == *"Fabric-only"* ]]
    ! grep -q '^lithium.jar$' "${MANAGED_FILE}"
}

# ---------------------------------------------------------------------------
# Geyser config — loader-aware path
# ---------------------------------------------------------------------------

@test "write_geyser_config writes Geyser-Spigot path for paper" {
    load_fabric_run "${FIXTURES_DIR}/options_fabric_defaults.json"
    write_geyser_config "paper"
    [ -f "${SERVER_DIR}/plugins/Geyser-Spigot/config.yml" ]
}

@test "write_geyser_config writes Geyser-Forge path for forge" {
    load_fabric_run "${FIXTURES_DIR}/options_fabric_defaults.json"
    write_geyser_config "forge"
    [ -f "${SERVER_DIR}/config/Geyser-Forge/config.yml" ]
}

@test "write_geyser_config writes Geyser-Fabric path for fabric" {
    load_fabric_run "${FIXTURES_DIR}/options_fabric_defaults.json"
    write_geyser_config "fabric"
    [ -f "${SERVER_DIR}/config/Geyser-Fabric/config.yml" ]
}

# ---------------------------------------------------------------------------
# extra_mods on a non-Fabric loader
# ---------------------------------------------------------------------------

@test "sync_server_mods tries extra_mods slugs for paper" {
    load_fabric_run "${FIXTURES_DIR}/options_fabric_rich.json"
    use_curl_mock
    MC_VERSION="1.21.4"
    sync_server_mods "paper" "${SERVER_DIR}/plugins"
    grep -q '^carpet.jar$' "${MANAGED_FILE}"
}
