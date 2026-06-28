#!/usr/bin/env bats
# Tests for persist_option() — writing the generated HMAC key back to the
# add-on options via the Supervisor API.

load helpers/common

setup() {
    setup_tmpdir
    load_invidious_run "${FIXTURES_DIR}/options_defaults.json"
    # Work on a writable copy so opt()/jq read a real file.
    cp "${OPTIONS}" "${TEST_TMPDIR}/options.json"
    OPTIONS="${TEST_TMPDIR}/options.json"
    CURL_BODY="${TEST_TMPDIR}/curl_body.json"
    SUPERVISOR_API="http://supervisor"
}

teardown() {
    teardown_tmpdir
}

# Records the -d payload and the target URL, then succeeds.
mock_supervisor_curl() {
    local body="" url="" prev=""
    local a
    for a in "$@"; do
        case "${prev}" in
            -d) body="${a}"; prev=""; continue;;
        esac
        case "${a}" in
            -d) prev="-d";;
            http://*|https://*) url="${a}";;
        esac
    done
    printf '%s' "${body}" > "${CURL_BODY}"
    printf '%s' "${url}" > "${CURL_BODY}.url"
    return 0
}

# Always fails, to exercise the error path.
mock_failing_curl() { return 22; }

@test "persist_option is a no-op when SUPERVISOR_TOKEN is unset" {
    unset SUPERVISOR_TOKEN
    curl() { mock_supervisor_curl "$@"; }
    run persist_option hmac_key "newkey123"
    [ "${status}" -eq 0 ]
    [ ! -f "${CURL_BODY}" ]
}

@test "persist_option does nothing when the option already matches" {
    export SUPERVISOR_TOKEN="token"
    curl() { mock_supervisor_curl "$@"; }
    # Default fixture has an empty hmac_key.
    run persist_option hmac_key ""
    [ "${status}" -eq 0 ]
    [ ! -f "${CURL_BODY}" ]
}

@test "persist_option posts merged options to the self/options endpoint" {
    export SUPERVISOR_TOKEN="token"
    curl() { mock_supervisor_curl "$@"; }

    persist_option hmac_key "deadbeefkey"

    [ -f "${CURL_BODY}" ]
    run jq -r '.options.hmac_key' "${CURL_BODY}"
    [ "${output}" = "deadbeefkey" ]
    # Other options are preserved in the payload.
    run jq -r '.options.domain' "${CURL_BODY}"
    [ "${output}" = "$(jq -r '.domain' "${OPTIONS}")" ]
    # Correct endpoint.
    [ "$(cat "${CURL_BODY}.url")" = "http://supervisor/addons/self/options" ]
}

@test "persist_option survives a failing Supervisor API call" {
    export SUPERVISOR_TOKEN="token"
    curl() { mock_failing_curl "$@"; }
    run persist_option hmac_key "deadbeefkey"
    [ "${status}" -eq 0 ]
}
