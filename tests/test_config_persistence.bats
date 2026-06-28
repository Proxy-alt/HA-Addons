#!/usr/bin/env bats
# Tests for config persistence: admin preference changes made through the
# Invidious web UI (saved to config.yml) must survive restarts, while changes
# to the HA add-on options must still regenerate the config.

load helpers/common

setup() {
    setup_tmpdir
    load_invidious_run "${FIXTURES_DIR}/options_defaults.json"
    # Use a writable copy of the options so we can simulate UI edits.
    cp "${OPTIONS}" "${TEST_TMPDIR}/options.json"
    OPTIONS="${TEST_TMPDIR}/options.json"
}

teardown() {
    teardown_tmpdir
}

@test "write_invidious_config records an options snapshot" {
    write_invidious_config
    [ -f "${CONFIG_FILE}" ]
    [ -f "${OPTIONS_SNAPSHOT}" ]
    run jq -e -n --slurpfile a "${OPTIONS}" --slurpfile b "${OPTIONS_SNAPSHOT}" '$a[0] == $b[0]'
    [ "${status}" -eq 0 ]
}

@test "config_is_current is false before any config is generated" {
    run config_is_current
    [ "${status}" -ne 0 ]
}

@test "config_is_current is false when the snapshot is missing" {
    : > "${CONFIG_FILE}"
    rm -f "${OPTIONS_SNAPSHOT}"
    run config_is_current
    [ "${status}" -ne 0 ]
}

@test "config_is_current is true once generated and options are unchanged" {
    write_invidious_config
    run config_is_current
    [ "${status}" -eq 0 ]
}

@test "admin web-UI changes survive a restart when options are unchanged" {
    write_invidious_config
    # Simulate Invidious rewriting config.yml after an admin changes a setting.
    printf 'popular_enabled: false  # changed via admin web UI\n' >> "${CONFIG_FILE}"

    # A subsequent start with the same options must NOT regenerate the file.
    write_invidious_config
    grep -q 'changed via admin web UI' "${CONFIG_FILE}"
}

@test "changing an HA option regenerates the config" {
    write_invidious_config
    printf 'admin marker\n' >> "${CONFIG_FILE}"

    # User edits an add-on option in the HA UI.
    jq '.domain = "example.com"' "${OPTIONS}" > "${TEST_TMPDIR}/opts2.json"
    OPTIONS="${TEST_TMPDIR}/opts2.json"

    write_invidious_config
    # The hand-added marker is gone (file was regenerated) ...
    ! grep -q 'admin marker' "${CONFIG_FILE}"
    # ... and the new option is reflected.
    grep -q 'domain: "example.com"' "${CONFIG_FILE}"
}
