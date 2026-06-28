#!/usr/bin/env bats
# Tests for invidious-companion/rootfs/run.sh

load helpers/common

COMPANION_SCRIPT="${REPO_DIR}/invidious-companion/rootfs/run.sh"

# ---------------------------------------------------------------------------
# Helper: build a per-test mock invidious_companion that writes its env to
# a file and exits, then run the companion script capturing output/status.
# ---------------------------------------------------------------------------
setup_env_capture() {
    local env_file="$1"
    local cap_bin="${TEST_TMPDIR}/cap_bin"
    mkdir -p "${cap_bin}"

    # Mock invidious_companion: dump env to file, then exit 0
    printf '#!/bin/bash\nenv > "%s"\nexit 0\n' "${env_file}" > "${cap_bin}/invidious_companion"
    chmod +x "${cap_bin}/invidious_companion"

    # TINI_BIN/COMPANION_BIN env vars are used by the companion script
    # (after our fix) so we don't need PATH tricks for the binaries.
    TINI_BIN="${MOCK_BIN_DIR}/tini"
    COMPANION_BIN="${cap_bin}/invidious_companion"
}

setup() {
    setup_tmpdir
}

teardown() {
    teardown_tmpdir
}

# ---------------------------------------------------------------------------
# Companion key validation
# ---------------------------------------------------------------------------

@test "companion exits 1 when companion_key is empty" {
    run env \
        BASHIO_LIB="${MOCK_BASHIO}" \
        OPTIONS="${FIXTURES_DIR}/companion_options_no_key.json" \
        bash "${COMPANION_SCRIPT}"
    [ "${status}" -eq 1 ]
}

@test "companion prints fatal error when companion_key is empty" {
    run env \
        BASHIO_LIB="${MOCK_BASHIO}" \
        OPTIONS="${FIXTURES_DIR}/companion_options_no_key.json" \
        bash "${COMPANION_SCRIPT}" 2>&1
    [[ "${output}" == *"Companion Key is not set"* ]]
}

# ---------------------------------------------------------------------------
# Environment variable exports
# ---------------------------------------------------------------------------

@test "SERVER_SECRET_KEY is exported from companion_key option" {
    local env_file="${TEST_TMPDIR}/companion_env.txt"
    setup_env_capture "${env_file}"

    env \
        BASHIO_LIB="${MOCK_BASHIO}" \
        OPTIONS="${FIXTURES_DIR}/companion_options.json" \
        TINI_BIN="${TINI_BIN}" \
        COMPANION_BIN="${COMPANION_BIN}" \
        bash "${COMPANION_SCRIPT}" 2>/dev/null

    [ -f "${env_file}" ]
    grep -q 'SERVER_SECRET_KEY=secret1234567890' "${env_file}"
}

@test "COMPANION_KEY is not leaked into environment" {
    local env_file="${TEST_TMPDIR}/companion_env.txt"
    setup_env_capture "${env_file}"

    env -i \
        BASHIO_LIB="${MOCK_BASHIO}" \
        OPTIONS="${FIXTURES_DIR}/companion_options.json" \
        TINI_BIN="${TINI_BIN}" \
        COMPANION_BIN="${COMPANION_BIN}" \
        bash "${COMPANION_SCRIPT}" 2>/dev/null

    [ -f "${env_file}" ]
    ! grep -q '^COMPANION_KEY=' "${env_file}"
}

@test "BACKEND_VIDEO_DOWNLOAD_THREADS is exported from download_threads option" {
    local env_file="${TEST_TMPDIR}/companion_env.txt"
    setup_env_capture "${env_file}"

    env \
        BASHIO_LIB="${MOCK_BASHIO}" \
        OPTIONS="${FIXTURES_DIR}/companion_options.json" \
        TINI_BIN="${TINI_BIN}" \
        COMPANION_BIN="${COMPANION_BIN}" \
        bash "${COMPANION_SCRIPT}" 2>/dev/null

    [ -f "${env_file}" ]
    grep -q 'BACKEND_VIDEO_DOWNLOAD_THREADS=4' "${env_file}"
}

@test "PORT is always exported as 8282" {
    local env_file="${TEST_TMPDIR}/companion_env.txt"
    setup_env_capture "${env_file}"

    env \
        BASHIO_LIB="${MOCK_BASHIO}" \
        OPTIONS="${FIXTURES_DIR}/companion_options.json" \
        TINI_BIN="${TINI_BIN}" \
        COMPANION_BIN="${COMPANION_BIN}" \
        bash "${COMPANION_SCRIPT}" 2>/dev/null

    [ -f "${env_file}" ]
    grep -q 'PORT=8282' "${env_file}"
}

@test "HOST is always exported as 0.0.0.0" {
    local env_file="${TEST_TMPDIR}/companion_env.txt"
    setup_env_capture "${env_file}"

    env \
        BASHIO_LIB="${MOCK_BASHIO}" \
        OPTIONS="${FIXTURES_DIR}/companion_options.json" \
        TINI_BIN="${TINI_BIN}" \
        COMPANION_BIN="${COMPANION_BIN}" \
        bash "${COMPANION_SCRIPT}" 2>/dev/null

    [ -f "${env_file}" ]
    grep -q 'HOST=0.0.0.0' "${env_file}"
}

# ---------------------------------------------------------------------------
# Proxy environment exports
# ---------------------------------------------------------------------------

@test "HTTP_PROXY is exported when http_proxy option is set" {
    local env_file="${TEST_TMPDIR}/companion_env.txt"
    setup_env_capture "${env_file}"

    env \
        BASHIO_LIB="${MOCK_BASHIO}" \
        OPTIONS="${FIXTURES_DIR}/companion_options_proxy.json" \
        TINI_BIN="${TINI_BIN}" \
        COMPANION_BIN="${COMPANION_BIN}" \
        bash "${COMPANION_SCRIPT}" 2>/dev/null

    [ -f "${env_file}" ]
    grep -q 'HTTP_PROXY=http://proxy.internal:3128' "${env_file}"
}

@test "HTTP_PROXY is not set when http_proxy option is empty" {
    local env_file="${TEST_TMPDIR}/companion_env.txt"
    setup_env_capture "${env_file}"

    env \
        BASHIO_LIB="${MOCK_BASHIO}" \
        OPTIONS="${FIXTURES_DIR}/companion_options.json" \
        TINI_BIN="${TINI_BIN}" \
        COMPANION_BIN="${COMPANION_BIN}" \
        bash "${COMPANION_SCRIPT}" 2>/dev/null

    [ -f "${env_file}" ]
    ! grep -q '^HTTP_PROXY=' "${env_file}"
}

@test "SOCKS_PROXY is exported when socks_proxy_host option is set" {
    local env_file="${TEST_TMPDIR}/companion_env.txt"
    setup_env_capture "${env_file}"

    env \
        BASHIO_LIB="${MOCK_BASHIO}" \
        OPTIONS="${FIXTURES_DIR}/companion_options_proxy.json" \
        TINI_BIN="${TINI_BIN}" \
        COMPANION_BIN="${COMPANION_BIN}" \
        bash "${COMPANION_SCRIPT}" 2>/dev/null

    [ -f "${env_file}" ]
    grep -q 'SOCKS_PROXY=socks.internal' "${env_file}"
    grep -q 'SOCKS_PORT=1080' "${env_file}"
}

@test "SOCKS_PROXY is not set when socks_proxy_host option is empty" {
    local env_file="${TEST_TMPDIR}/companion_env.txt"
    setup_env_capture "${env_file}"

    env \
        BASHIO_LIB="${MOCK_BASHIO}" \
        OPTIONS="${FIXTURES_DIR}/companion_options.json" \
        TINI_BIN="${TINI_BIN}" \
        COMPANION_BIN="${COMPANION_BIN}" \
        bash "${COMPANION_SCRIPT}" 2>/dev/null

    [ -f "${env_file}" ]
    ! grep -q '^SOCKS_PROXY=' "${env_file}"
}
