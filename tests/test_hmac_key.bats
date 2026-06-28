#!/usr/bin/env bats
# Tests for the resolve_hmac_key() function.

load helpers/common

setup() {
    setup_tmpdir
    load_invidious_run "${FIXTURES_DIR}/options_defaults.json"
    CONFIG_DIR="${TEST_TMPDIR}/invidious"
}

teardown() {
    teardown_tmpdir
}

# ---------------------------------------------------------------------------
# HMAC key from options.json
# ---------------------------------------------------------------------------

@test "hmac_key from options.json is used when set" {
    # Inject an hmac_key directly into the options fixture
    local opts_with_key="${TEST_TMPDIR}/opts_key.json"
    jq '.hmac_key = "userprovidedkey1234567890abcdef"' "${OPTIONS}" > "${opts_with_key}"
    OPTIONS="${opts_with_key}"

    resolve_hmac_key
    [ "${HMAC_KEY}" = "userprovidedkey1234567890abcdef" ]
}

# ---------------------------------------------------------------------------
# HMAC key from persisted file
# ---------------------------------------------------------------------------

@test "hmac_key is read from persisted file when options value is empty" {
    mkdir -p "${CONFIG_DIR}"
    printf 'persistedhmackey1234567890abcdef' > "${CONFIG_DIR}/.hmac_key"

    resolve_hmac_key
    [ "${HMAC_KEY}" = "persistedhmackey1234567890abcdef" ]
}

@test "persisted hmac_key file takes precedence over openssl generation" {
    mkdir -p "${CONFIG_DIR}"
    printf 'fromfile1234567890abcdef12345678' > "${CONFIG_DIR}/.hmac_key"

    resolve_hmac_key
    # Should NOT be the mock openssl output
    [ "${HMAC_KEY}" != "deadbeef12345678deadbeef12345678deadbeef12345678deadbeef12345678" ]
    [ "${HMAC_KEY}" = "fromfile1234567890abcdef12345678" ]
}

# ---------------------------------------------------------------------------
# HMAC key auto-generated
# ---------------------------------------------------------------------------

@test "hmac_key is auto-generated when options and file are both empty" {
    # CONFIG_DIR is empty, OPTIONS has empty hmac_key
    resolve_hmac_key

    # Mock openssl returns a fixed value
    [ "${HMAC_KEY}" = "deadbeef12345678deadbeef12345678deadbeef12345678deadbeef12345678" ]
}

@test "auto-generated hmac_key is persisted to file" {
    resolve_hmac_key

    local key_file="${CONFIG_DIR}/.hmac_key"
    [ -f "${key_file}" ]
    [ "$(cat "${key_file}")" = "${HMAC_KEY}" ]
}

@test "auto-generated hmac_key file has mode 600" {
    resolve_hmac_key

    local key_file="${CONFIG_DIR}/.hmac_key"
    local mode
    mode="$(stat -f '%A' "${key_file}" 2>/dev/null || stat -c '%a' "${key_file}")"
    [ "${mode}" = "600" ]
}

@test "second call reuses the persisted key rather than generating a new one" {
    # First call: generates and persists key
    resolve_hmac_key
    local first_key="${HMAC_KEY}"

    # Second call: should read from file
    HMAC_KEY=""
    resolve_hmac_key
    [ "${HMAC_KEY}" = "${first_key}" ]
}

# ---------------------------------------------------------------------------
# Error path
# ---------------------------------------------------------------------------

@test "resolve_hmac_key fails if openssl mock returns empty" {
    # Temporarily replace mock openssl with one that returns nothing
    local bad_openssl="${TEST_TMPDIR}/bin/openssl"
    mkdir -p "${TEST_TMPDIR}/bin"
    printf '#!/bin/bash\nprintf ""\n' > "${bad_openssl}"
    chmod +x "${bad_openssl}"
    PATH="${TEST_TMPDIR}/bin:${PATH}"

    run resolve_hmac_key
    [ "${status}" -ne 0 ]
}
