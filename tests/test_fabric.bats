#!/usr/bin/env bats
# Tests for fabric-server/rootfs/run.sh

load helpers/common

FABRIC_SCRIPT="${REPO_DIR}/fabric-server/rootfs/run.sh"

setup() {
    setup_tmpdir
}

teardown() {
    teardown_tmpdir
}

# Activate the offline curl mock for the current shell.
use_curl_mock() {
    curl() { fabric_mock_curl "$@"; }
}

# ---------------------------------------------------------------------------
# EULA
# ---------------------------------------------------------------------------

@test "handle_eula returns 1 when EULA not accepted" {
    load_fabric_run "${FIXTURES_DIR}/options_fabric_no_eula.json"
    run handle_eula
    [ "${status}" -eq 1 ]
}

@test "handle_eula prints a fatal message when EULA not accepted" {
    load_fabric_run "${FIXTURES_DIR}/options_fabric_no_eula.json"
    run handle_eula
    [[ "${output}" == *"EULA"* ]]
}

@test "handle_eula writes eula.txt when accepted" {
    load_fabric_run "${FIXTURES_DIR}/options_fabric_defaults.json"
    handle_eula
    [ -f "${SERVER_DIR}/eula.txt" ]
    grep -q '^eula=true$' "${SERVER_DIR}/eula.txt"
}

# ---------------------------------------------------------------------------
# server.properties
# ---------------------------------------------------------------------------

@test "write_server_properties maps options to properties" {
    load_fabric_run "${FIXTURES_DIR}/options_fabric_defaults.json"
    write_server_properties
    local f="${SERVER_DIR}/server.properties"
    grep -q '^motd=A Fabric server$' "${f}"
    grep -q '^difficulty=normal$' "${f}"
    grep -q '^max-players=20$' "${f}"
    grep -q '^online-mode=true$' "${f}"
    grep -q '^level-type=minecraft:normal$' "${f}"
    grep -q '^server-port=25565$' "${f}"
}

@test "write_server_properties reflects boolean false without dropping it" {
    load_fabric_run "${FIXTURES_DIR}/options_fabric_defaults.json"
    write_server_properties
    grep -q '^hardcore=false$' "${SERVER_DIR}/server.properties"
    grep -q '^pvp=true$' "${SERVER_DIR}/server.properties"
}

@test "write_server_properties honors whitelist + offline mode from rich fixture" {
    load_fabric_run "${FIXTURES_DIR}/options_fabric_rich.json"
    write_server_properties
    grep -q '^online-mode=false$' "${SERVER_DIR}/server.properties"
    grep -q '^white-list=true$' "${SERVER_DIR}/server.properties"
    grep -q '^enforce-whitelist=true$' "${SERVER_DIR}/server.properties"
    grep -q '^hardcore=true$' "${SERVER_DIR}/server.properties"
}

# ---------------------------------------------------------------------------
# Geyser config
# ---------------------------------------------------------------------------

@test "write_geyser_config uses floodgate auth when floodgate enabled" {
    load_fabric_run "${FIXTURES_DIR}/options_fabric_defaults.json"
    write_geyser_config
    local f="${SERVER_DIR}/config/Geyser-Fabric/config.yml"
    [ -f "${f}" ]
    grep -q 'auth-type: floodgate' "${f}"
    grep -q 'port: 19132' "${f}"
}

@test "write_geyser_config uses online auth when floodgate disabled" {
    load_fabric_run "${FIXTURES_DIR}/options_fabric_no_floodgate.json"
    write_geyser_config
    grep -q 'auth-type: online' "${SERVER_DIR}/config/Geyser-Fabric/config.yml"
}

@test "write_geyser_config writes nothing when geyser disabled" {
    load_fabric_run "${FIXTURES_DIR}/options_fabric_no_geyser.json"
    write_geyser_config
    [ ! -f "${SERVER_DIR}/config/Geyser-Fabric/config.yml" ]
}

@test "geyser config is valid YAML" {
    load_fabric_run "${FIXTURES_DIR}/options_fabric_defaults.json"
    write_geyser_config
    assert_valid_yaml "${SERVER_DIR}/config/Geyser-Fabric/config.yml"
}

# ---------------------------------------------------------------------------
# JVM args
# ---------------------------------------------------------------------------

@test "build_jvm_args sets heap from options" {
    load_fabric_run "${FIXTURES_DIR}/options_fabric_defaults.json"
    build_jvm_args
    [[ " ${JVM_ARGS[*]} " == *" -Xms1G "* ]]
    [[ " ${JVM_ARGS[*]} " == *" -Xmx2G "* ]]
    [[ " ${JVM_ARGS[*]} " == *" -XX:+UseG1GC "* ]]
}

@test "build_jvm_args appends extra java_args last" {
    load_fabric_run "${FIXTURES_DIR}/options_fabric_rich.json"
    build_jvm_args
    local last="${JVM_ARGS[$((${#JVM_ARGS[@]} - 1))]}"
    [ "${last}" = "-Dfoo=bar" ]
}

@test "build_jvm_args omits extra args when java_args empty" {
    load_fabric_run "${FIXTURES_DIR}/options_fabric_defaults.json"
    build_jvm_args
    [[ " ${JVM_ARGS[*]} " != *" -Dfoo=bar "* ]]
}

# ---------------------------------------------------------------------------
# Version resolution (offline curl mock)
# ---------------------------------------------------------------------------

@test "resolve_versions keeps a pinned minecraft version" {
    load_fabric_run "${FIXTURES_DIR}/options_fabric_defaults.json"
    use_curl_mock
    resolve_versions
    [ "${MC_VERSION}" = "1.21.4" ]
}

# ---------------------------------------------------------------------------
# Mod synchronisation (offline curl mock)
# ---------------------------------------------------------------------------

@test "sync_mods installs enabled mods plus fabric-api" {
    load_fabric_run "${FIXTURES_DIR}/options_fabric_defaults.json"
    use_curl_mock
    MC_VERSION="1.21.4"
    sync_mods
    grep -q '^fabric-api.jar$' "${MANAGED_FILE}"
    grep -q '^lithium.jar$' "${MANAGED_FILE}"
    grep -q '^ferrite-core.jar$' "${MANAGED_FILE}"
    grep -q '^geyser.jar$' "${MANAGED_FILE}"
    grep -q '^floodgate.jar$' "${MANAGED_FILE}"
}

@test "sync_mods skips disabled mods" {
    load_fabric_run "${FIXTURES_DIR}/options_fabric_defaults.json"
    use_curl_mock
    MC_VERSION="1.21.4"
    sync_mods
    ! grep -q '^c2me-fabric.jar$' "${MANAGED_FILE}"
    ! grep -q '^servercore.jar$' "${MANAGED_FILE}"
}

@test "sync_mods installs extra mods by slug" {
    load_fabric_run "${FIXTURES_DIR}/options_fabric_rich.json"
    use_curl_mock
    MC_VERSION="1.21.4"
    sync_mods
    grep -q '^carpet.jar$' "${MANAGED_FILE}"
    grep -q '^c2me-fabric.jar$' "${MANAGED_FILE}"
}

@test "sync_mods skips a mod with no matching build" {
    load_fabric_run "${FIXTURES_DIR}/options_fabric_defaults.json"
    use_curl_mock
    export FABRIC_MOCK_EMPTY="krypton"
    MC_VERSION="1.21.4"
    sync_mods
    ! grep -q '^krypton.jar$' "${MANAGED_FILE}"
    grep -q '^lithium.jar$' "${MANAGED_FILE}"
}

@test "sync_mods removes previously managed mods" {
    load_fabric_run "${FIXTURES_DIR}/options_fabric_defaults.json"
    use_curl_mock
    MC_VERSION="1.21.4"
    # Simulate a stale managed mod from a previous run.
    echo "stale-mod.jar" > "${MANAGED_FILE}"
    touch "${MODS_DIR}/stale-mod.jar"
    sync_mods
    [ ! -f "${MODS_DIR}/stale-mod.jar" ]
    ! grep -q '^stale-mod.jar$' "${MANAGED_FILE}"
}

@test "sync_mods preserves user-dropped jars" {
    load_fabric_run "${FIXTURES_DIR}/options_fabric_defaults.json"
    use_curl_mock
    MC_VERSION="1.21.4"
    touch "${MODS_DIR}/my-custom-mod.jar"
    sync_mods
    [ -f "${MODS_DIR}/my-custom-mod.jar" ]
}

# ---------------------------------------------------------------------------
# ops.json (offline curl mock for Mojang)
# ---------------------------------------------------------------------------

@test "apply_ops resolves usernames to hyphenated UUIDs" {
    load_fabric_run "${FIXTURES_DIR}/options_fabric_rich.json"
    use_curl_mock
    apply_ops
    local f="${SERVER_DIR}/ops.json"
    [ -f "${f}" ]
    run jq -r '.[0].uuid' "${f}"
    [ "${output}" = "853c80ef-3c37-49fd-aa49-938b674adae6" ]
    run jq -r '.[0].level' "${f}"
    [ "${output}" = "4" ]
}

@test "apply_ops writes an empty array when ops list empty" {
    load_fabric_run "${FIXTURES_DIR}/options_fabric_defaults.json"
    use_curl_mock
    apply_ops
    [ -f "${SERVER_DIR}/ops.json" ]
    run jq 'length' "${SERVER_DIR}/ops.json"
    [ "${output}" = "0" ]
}

# ---------------------------------------------------------------------------
# whitelist.json (offline curl mock for Mojang)
# ---------------------------------------------------------------------------

@test "apply_whitelist resolves names to UUID entries" {
    load_fabric_run "${FIXTURES_DIR}/options_fabric_defaults.json"
    cp "${OPTIONS}" "${TEST_TMPDIR}/opts.json"
    jq '.whitelist = ["Notch"]' "${TEST_TMPDIR}/opts.json" > "${TEST_TMPDIR}/opts2.json"
    OPTIONS="${TEST_TMPDIR}/opts2.json"
    use_curl_mock
    apply_whitelist
    local f="${SERVER_DIR}/whitelist.json"
    [ -f "${f}" ]
    run jq -r '.[0].name' "${f}"
    [ "${output}" = "Notch" ]
    run jq -r '.[0].uuid' "${f}"
    [ "${output}" = "853c80ef-3c37-49fd-aa49-938b674adae6" ]
}

@test "apply_whitelist writes an empty array when whitelist empty" {
    load_fabric_run "${FIXTURES_DIR}/options_fabric_defaults.json"
    use_curl_mock
    apply_whitelist
    [ -f "${SERVER_DIR}/whitelist.json" ]
    run jq 'length' "${SERVER_DIR}/whitelist.json"
    [ "${output}" = "0" ]
}

# ---------------------------------------------------------------------------
# Three-way list merge (merge_list)
# ---------------------------------------------------------------------------

@test "merge_list unions option and live entries when no baseline" {
    load_fabric_run "${FIXTURES_DIR}/options_fabric_rich.json"   # ops: ["jeb_"]
    local result
    result="$(printf 'alice\n' | merge_list ops "${OPS_BASELINE}")"
    echo "${result}" | jq -e 'sort == ["alice","jeb_"]'
}

@test "merge_list keeps an entry added only via the options" {
    load_fabric_run "${FIXTURES_DIR}/options_fabric_rich.json"   # ops: ["jeb_"]
    : > "${OPS_BASELINE}"                                        # empty baseline
    local result
    result="$(printf '' | merge_list ops "${OPS_BASELINE}")"
    echo "${result}" | jq -e '. == ["jeb_"]'
}

@test "merge_list drops an entry removed in-game" {
    load_fabric_run "${FIXTURES_DIR}/options_fabric_rich.json"   # ops: ["jeb_"]
    printf 'jeb_\n' > "${OPS_BASELINE}"                          # jeb_ was synced before
    # In-game /deop removed jeb_ from the live file; the option still lists it.
    local result
    result="$(printf '' | merge_list ops "${OPS_BASELINE}")"
    echo "${result}" | jq -e 'length == 0'
}

@test "merge_list refreshes the baseline with the merged set" {
    load_fabric_run "${FIXTURES_DIR}/options_fabric_rich.json"   # ops: ["jeb_"]
    printf 'alice\n' | merge_list ops "${OPS_BASELINE}" >/dev/null
    grep -q '^alice$' "${OPS_BASELINE}"
    grep -q '^jeb_$' "${OPS_BASELINE}"
}

# ---------------------------------------------------------------------------
# Runtime → options sync (sync_runtime_config)
# ---------------------------------------------------------------------------

# Copy the fixture to a writable file so sync_runtime_config can rewrite it.
writable_options() {
    cp "${OPTIONS}" "${TEST_TMPDIR}/live_options.json"
    OPTIONS="${TEST_TMPDIR}/live_options.json"
}

@test "sync_runtime_config pulls an in-game op back into the options" {
    load_fabric_run "${FIXTURES_DIR}/options_fabric_defaults.json"
    writable_options
    unset SUPERVISOR_TOKEN
    # Simulate /op steve recorded by the server last session.
    cat > "${SERVER_DIR}/ops.json" <<'JSON'
[{"uuid":"00000000-0000-0000-0000-000000000001","name":"steve","level":4,"bypassesPlayerLimit":false}]
JSON
    sync_runtime_config
    run jq -r '.ops[]' "${OPTIONS}"
    [ "${output}" = "steve" ]
    grep -q '^steve$' "${OPS_BASELINE}"
}

@test "sync_runtime_config pulls an in-game whitelist add back into the options" {
    load_fabric_run "${FIXTURES_DIR}/options_fabric_defaults.json"
    writable_options
    unset SUPERVISOR_TOKEN
    cat > "${SERVER_DIR}/whitelist.json" <<'JSON'
[{"uuid":"00000000-0000-0000-0000-000000000002","name":"alice"}]
JSON
    sync_runtime_config
    run jq -r '.whitelist[]' "${OPTIONS}"
    [ "${output}" = "alice" ]
}

@test "sync_runtime_config leaves options untouched when nothing changed" {
    load_fabric_run "${FIXTURES_DIR}/options_fabric_defaults.json"
    writable_options
    unset SUPERVISOR_TOKEN
    local before
    before="$(jq -S . "${OPTIONS}")"
    sync_runtime_config
    local after
    after="$(jq -S . "${OPTIONS}")"
    [ "${before}" = "${after}" ]
}

@test "sync_runtime_config posts to the Supervisor API when a token is set" {
    load_fabric_run "${FIXTURES_DIR}/options_fabric_defaults.json"
    writable_options
    export SUPERVISOR_TOKEN="token"
    SUPERVISOR_API="http://supervisor"
    local body_file="${TEST_TMPDIR}/body.json"
    # Record the POST body; route Mojang lookups to the offline mock.
    curl() {
        local body="" prev="" a
        for a in "$@"; do
            case "${prev}" in -d) body="${a}"; prev="";; esac
            case "${a}" in -d) prev="-d";; esac
        done
        if [[ -n "${body}" ]]; then printf '%s' "${body}" > "${body_file}"; return 0; fi
        fabric_mock_curl "$@"
    }
    cat > "${SERVER_DIR}/ops.json" <<'JSON'
[{"uuid":"00000000-0000-0000-0000-000000000001","name":"steve","level":4}]
JSON
    sync_runtime_config
    [ -f "${body_file}" ]
    run jq -r '.options.ops[]' "${body_file}"
    [ "${output}" = "steve" ]
}
