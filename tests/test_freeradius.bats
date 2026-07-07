#!/usr/bin/env bats
# Tests for freeradius/rootfs/run.sh

load helpers/common

setup() {
    setup_tmpdir
    load_freeradius_run
}

teardown() {
    teardown_tmpdir
}

# ---------------------------------------------------------------------------
# clients.conf generation
# ---------------------------------------------------------------------------

@test "writes a client block from the clients list" {
    write_clients_conf

    assert_file_contains_path "${CLIENTS_CONF}" "client hostapd {"
    assert_file_contains_path "${CLIENTS_CONF}" "ipaddr = 192.168.1.10"
    assert_file_contains_path "${CLIENTS_CONF}" "secret = radiussecret1"
}

@test "refuses to start with an empty clients list" {
    load_freeradius_run "${FIXTURES_DIR}/options_freeradius_no_clients.json"

    run write_clients_conf
    [ "${status}" -ne 0 ]
}

@test "refuses to start with an incomplete client entry" {
    load_freeradius_run "${FIXTURES_DIR}/options_freeradius_incomplete_client.json"

    run write_clients_conf
    [ "${status}" -ne 0 ]
}

# ---------------------------------------------------------------------------
# users file generation
# ---------------------------------------------------------------------------

@test "writes a Cleartext-Password line per configured user" {
    write_users_file

    assert_file_contains_path "${USERS_FILE}" 'alice	Cleartext-Password := "hunter2"'
}

@test "writes an empty users file when no users are configured" {
    load_freeradius_run "${FIXTURES_DIR}/options_freeradius_no_users.json"

    run write_users_file
    [ "${status}" -eq 0 ]
    [ ! -s "${USERS_FILE}" ]
}

# ---------------------------------------------------------------------------
# EAP configuration
# ---------------------------------------------------------------------------

@test "write_eap_config sets default_eap_type and cert paths" {
    write_eap_config

    assert_file_contains_path "${EAP_FILE}" "default_eap_type = peap"
    assert_file_contains_path "${EAP_FILE}" "private_key_file = ${CERTS_DIR}/server.key"
    assert_file_contains_path "${EAP_FILE}" "certificate_file = ${CERTS_DIR}/server.pem"
    assert_file_contains_path "${EAP_FILE}" "ca_file = ${CERTS_DIR}/ca.pem"
}

@test "write_eap_config sets require_client_cert = no when tls_verify_client_cert is false" {
    write_eap_config
    assert_file_contains_path "${EAP_FILE}" "require_client_cert = no"
}

@test "write_eap_config sets require_client_cert = yes and default_eap_type = tls for EAP-TLS" {
    load_freeradius_run "${FIXTURES_DIR}/options_freeradius_no_users.json"

    write_eap_config

    assert_file_contains_path "${EAP_FILE}" "default_eap_type = tls"
    assert_file_contains_path "${EAP_FILE}" "require_client_cert = yes"
}

@test "write_eap_config leaves the ttls/peap inner-tunnel EAP methods as md5/mschapv2" {
    write_eap_config

    # The top-level directive reflects the configured option...
    assert_file_contains_path "${EAP_FILE}" "default_eap_type = peap"
    # ...while the ttls/peap sub-blocks keep their own inner-tunnel method,
    # which is unrelated to the outer EAP type offered to the client.
    assert_file_contains_path "${EAP_FILE}" "	default_eap_type = md5"
    assert_file_contains_path "${EAP_FILE}" "	default_eap_type = mschapv2"
}

# ---------------------------------------------------------------------------
# Certificate generation
# ---------------------------------------------------------------------------

@test "generate_certs creates a CA and server certificate" {
    generate_certs

    [ -f "${CERTS_DIR}/ca.pem" ]
    [ -f "${CERTS_DIR}/server.pem" ]
    [ -f "${CERTS_DIR}/server.key" ]
}

@test "generate_certs does not regenerate existing certificates" {
    generate_certs
    local first_cert
    first_cert="$(cat "${CERTS_DIR}/server.pem")"

    generate_certs
    [ "$(cat "${CERTS_DIR}/server.pem")" = "${first_cert}" ]
}

@test "generate_certs restricts private key permissions" {
    generate_certs

    local mode
    mode="$(stat -f '%A' "${CERTS_DIR}/server.key" 2>/dev/null || stat -c '%a' "${CERTS_DIR}/server.key")"
    [ "${mode}" = "600" ]
}
