#!/usr/bin/env bats
# Tests for playit/rootfs/run.sh

load helpers/common

PLAYIT_SCRIPT="${REPO_DIR}/playit/rootfs/run.sh"

# ---------------------------------------------------------------------------
# Helper: install a mock playit binary that dumps its environment to a file,
# then run the playit script capturing output and status.
# ---------------------------------------------------------------------------
setup_env_capture() {
    local env_file="$1"
    local cap_bin="${TEST_TMPDIR}/cap_bin"
    mkdir -p "${cap_bin}"

    printf '#!/bin/bash\nenv > "%s"\nexit 0\n' "${env_file}" > "${cap_bin}/playit"
    chmod +x "${cap_bin}/playit"

    PLAYIT_BIN="${cap_bin}/playit"
}

setup() {
    setup_tmpdir
}

teardown() {
    teardown_tmpdir
}

# ---------------------------------------------------------------------------
# PLAYIT_SECRET export
# ---------------------------------------------------------------------------

@test "PLAYIT_SECRET is exported when secret_key is set" {
    local env_file="${TEST_TMPDIR}/playit_env.txt"
    setup_env_capture "${env_file}"

    env \
        BASHIO_LIB="${MOCK_BASHIO}" \
        OPTIONS="${FIXTURES_DIR}/playit_options.json" \
        PLAYIT_BIN="${PLAYIT_BIN}" \
        PLAYIT_HOME="${TEST_TMPDIR}/data" \
        bash "${PLAYIT_SCRIPT}" 2>/dev/null

    [ -f "${env_file}" ]
    grep -q 'PLAYIT_SECRET=test-secret-key-abc123' "${env_file}"
}

@test "PLAYIT_SECRET is not set when secret_key is empty" {
    local env_file="${TEST_TMPDIR}/playit_env.txt"
    setup_env_capture "${env_file}"

    env \
        BASHIO_LIB="${MOCK_BASHIO}" \
        OPTIONS="${FIXTURES_DIR}/playit_options_no_key.json" \
        PLAYIT_BIN="${PLAYIT_BIN}" \
        PLAYIT_HOME="${TEST_TMPDIR}/data" \
        bash "${PLAYIT_SCRIPT}" 2>/dev/null

    [ -f "${env_file}" ]
    ! grep -q '^PLAYIT_SECRET=' "${env_file}"
}

# ---------------------------------------------------------------------------
# HOME redirect for config persistence
# ---------------------------------------------------------------------------

@test "HOME is set to PLAYIT_HOME" {
    local env_file="${TEST_TMPDIR}/playit_env.txt"
    setup_env_capture "${env_file}"

    env \
        BASHIO_LIB="${MOCK_BASHIO}" \
        OPTIONS="${FIXTURES_DIR}/playit_options.json" \
        PLAYIT_BIN="${PLAYIT_BIN}" \
        PLAYIT_HOME="${TEST_TMPDIR}/data" \
        bash "${PLAYIT_SCRIPT}" 2>/dev/null

    [ -f "${env_file}" ]
    grep -q "HOME=${TEST_TMPDIR}/data" "${env_file}"
}

@test "config directory is created under PLAYIT_HOME" {
    local env_file="${TEST_TMPDIR}/playit_env.txt"
    setup_env_capture "${env_file}"

    env \
        BASHIO_LIB="${MOCK_BASHIO}" \
        OPTIONS="${FIXTURES_DIR}/playit_options.json" \
        PLAYIT_BIN="${PLAYIT_BIN}" \
        PLAYIT_HOME="${TEST_TMPDIR}/data" \
        bash "${PLAYIT_SCRIPT}" 2>/dev/null

    [ -d "${TEST_TMPDIR}/data/.config/playit" ]
}

# ---------------------------------------------------------------------------
# No-key warning (informational — does not exit with error)
# ---------------------------------------------------------------------------

@test "playit runs without error when secret_key is empty" {
    local env_file="${TEST_TMPDIR}/playit_env.txt"
    setup_env_capture "${env_file}"

    run env \
        BASHIO_LIB="${MOCK_BASHIO}" \
        OPTIONS="${FIXTURES_DIR}/playit_options_no_key.json" \
        PLAYIT_BIN="${PLAYIT_BIN}" \
        PLAYIT_HOME="${TEST_TMPDIR}/data" \
        bash "${PLAYIT_SCRIPT}" 2>/dev/null

    [ "${status}" -eq 0 ]
}

@test "playit binary is invoked even when secret_key is empty" {
    local env_file="${TEST_TMPDIR}/playit_env.txt"
    setup_env_capture "${env_file}"

    env \
        BASHIO_LIB="${MOCK_BASHIO}" \
        OPTIONS="${FIXTURES_DIR}/playit_options_no_key.json" \
        PLAYIT_BIN="${PLAYIT_BIN}" \
        PLAYIT_HOME="${TEST_TMPDIR}/data" \
        bash "${PLAYIT_SCRIPT}" 2>/dev/null

    [ -f "${env_file}" ]
}
