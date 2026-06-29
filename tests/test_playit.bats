#!/usr/bin/env bats
# Tests for playit/rootfs/run.sh

load helpers/common

PLAYIT_SCRIPT="${REPO_DIR}/playit/rootfs/run.sh"

# ---------------------------------------------------------------------------
# Helper: install a mock playitd binary that dumps its args to a file,
# then run the playit script.
# ---------------------------------------------------------------------------
setup_arg_capture() {
    local args_file="$1"
    local cap_bin="${TEST_TMPDIR}/cap_bin"
    mkdir -p "${cap_bin}"

    printf '#!/bin/bash\necho "$@" > "%s"\nexit 0\n' "${args_file}" > "${cap_bin}/playitd"
    chmod +x "${cap_bin}/playitd"

    PLAYITD_BIN="${cap_bin}/playitd"
}

setup() {
    setup_tmpdir
}

teardown() {
    teardown_tmpdir
}

# ---------------------------------------------------------------------------
# Secret file generation
# ---------------------------------------------------------------------------

@test "secret TOML file is written when secret_key is configured" {
    local args_file="${TEST_TMPDIR}/args.txt"
    local secret_path="${TEST_TMPDIR}/playit.toml"
    setup_arg_capture "${args_file}"

    env \
        BASHIO_LIB="${MOCK_BASHIO}" \
        OPTIONS="${FIXTURES_DIR}/playit_options.json" \
        PLAYITD_BIN="${PLAYITD_BIN}" \
        SECRET_PATH="${secret_path}" \
        SOCKET_DIR="${TEST_TMPDIR}/run-playit" \
        bash "${PLAYIT_SCRIPT}" 2>/dev/null

    [ -f "${secret_path}" ]
    grep -q 'secret_key = "test-secret-key-abc123"' "${secret_path}"
}

@test "secret TOML file is not written when secret_key is empty" {
    local args_file="${TEST_TMPDIR}/args.txt"
    local secret_path="${TEST_TMPDIR}/playit.toml"
    setup_arg_capture "${args_file}"

    env \
        BASHIO_LIB="${MOCK_BASHIO}" \
        OPTIONS="${FIXTURES_DIR}/playit_options_no_key.json" \
        PLAYITD_BIN="${PLAYITD_BIN}" \
        SECRET_PATH="${secret_path}" \
        SOCKET_DIR="${TEST_TMPDIR}/run-playit" \
        bash "${PLAYIT_SCRIPT}" 2>/dev/null

    [ ! -f "${secret_path}" ]
}

# ---------------------------------------------------------------------------
# Socket directory creation
# ---------------------------------------------------------------------------

@test "socket directory is created before playitd is started" {
    local args_file="${TEST_TMPDIR}/args.txt"
    setup_arg_capture "${args_file}"

    env \
        BASHIO_LIB="${MOCK_BASHIO}" \
        OPTIONS="${FIXTURES_DIR}/playit_options.json" \
        PLAYITD_BIN="${PLAYITD_BIN}" \
        SECRET_PATH="${TEST_TMPDIR}/playit.toml" \
        SOCKET_DIR="${TEST_TMPDIR}/run-playit" \
        bash "${PLAYIT_SCRIPT}" 2>/dev/null

    [ -d "${TEST_TMPDIR}/run-playit" ]
}

# ---------------------------------------------------------------------------
# playitd invocation flags
# ---------------------------------------------------------------------------

@test "playitd is invoked with --secret-path flag" {
    local args_file="${TEST_TMPDIR}/args.txt"
    local secret_path="${TEST_TMPDIR}/playit.toml"
    setup_arg_capture "${args_file}"

    env \
        BASHIO_LIB="${MOCK_BASHIO}" \
        OPTIONS="${FIXTURES_DIR}/playit_options.json" \
        PLAYITD_BIN="${PLAYITD_BIN}" \
        SECRET_PATH="${secret_path}" \
        SOCKET_DIR="${TEST_TMPDIR}/run-playit" \
        bash "${PLAYIT_SCRIPT}" 2>/dev/null

    grep -q -- "--secret-path ${secret_path}" "${args_file}"
}

@test "playitd is invoked with --socket-path flag" {
    local args_file="${TEST_TMPDIR}/args.txt"
    setup_arg_capture "${args_file}"

    env \
        BASHIO_LIB="${MOCK_BASHIO}" \
        OPTIONS="${FIXTURES_DIR}/playit_options.json" \
        PLAYITD_BIN="${PLAYITD_BIN}" \
        SECRET_PATH="${TEST_TMPDIR}/playit.toml" \
        SOCKET_DIR="${TEST_TMPDIR}/run-playit" \
        bash "${PLAYIT_SCRIPT}" 2>/dev/null

    grep -q -- "--socket-path ${TEST_TMPDIR}/run-playit/playitd.sock" "${args_file}"
}

# ---------------------------------------------------------------------------
# No-key startup — daemon still runs (handles claim flow itself)
# ---------------------------------------------------------------------------

@test "playitd is started even when secret_key is empty" {
    local args_file="${TEST_TMPDIR}/args.txt"
    setup_arg_capture "${args_file}"

    run env \
        BASHIO_LIB="${MOCK_BASHIO}" \
        OPTIONS="${FIXTURES_DIR}/playit_options_no_key.json" \
        PLAYITD_BIN="${PLAYITD_BIN}" \
        SECRET_PATH="${TEST_TMPDIR}/playit.toml" \
        SOCKET_DIR="${TEST_TMPDIR}/run-playit" \
        bash "${PLAYIT_SCRIPT}" 2>/dev/null

    [ "${status}" -eq 0 ]
    [ -f "${args_file}" ]
}
