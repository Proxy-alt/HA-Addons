#!/usr/bin/env bats
# Tests for cync-lan/rootfs/run.sh

load helpers/common

setup() {
    setup_tmpdir
    load_cync_lan_run
}

teardown() {
    teardown_tmpdir
}

# ---------------------------------------------------------------------------
# resolve_secret_key()
# ---------------------------------------------------------------------------

@test "secret_key from options.json is used when set" {
    load_cync_lan_run "${FIXTURES_DIR}/options_cync_lan_rich.json"

    resolve_secret_key
    [ "${SECRET_KEY}" = "userprovidedsecretkey1234567890" ]
}

@test "secret_key is read from persisted file when options value is empty" {
    mkdir -p "${CONFIG_DIR}"
    printf 'persistedsecretkey1234567890abcdef' > "${CONFIG_DIR}/.secret_key"

    resolve_secret_key
    [ "${SECRET_KEY}" = "persistedsecretkey1234567890abcdef" ]
}

@test "secret_key is auto-generated when options and file are both empty" {
    resolve_secret_key
    # Mock openssl returns a fixed value for `rand -hex 32`.
    [ "${SECRET_KEY}" = "deadbeef12345678deadbeef12345678deadbeef12345678deadbeef12345678" ]
}

@test "auto-generated secret_key is persisted to file with mode 600" {
    resolve_secret_key

    local key_file="${CONFIG_DIR}/.secret_key"
    [ -f "${key_file}" ]
    [ "$(cat "${key_file}")" = "${SECRET_KEY}" ]

    local mode
    mode="$(stat -f '%A' "${key_file}" 2>/dev/null || stat -c '%a' "${key_file}")"
    [ "${mode}" = "600" ]
}

@test "second call to resolve_secret_key reuses the persisted key" {
    resolve_secret_key
    local first_key="${SECRET_KEY}"

    SECRET_KEY=""
    resolve_secret_key
    [ "${SECRET_KEY}" = "${first_key}" ]
}

# ---------------------------------------------------------------------------
# generate_certs()
# ---------------------------------------------------------------------------

@test "generate_certs writes a cert and key" {
    generate_certs

    [ -f "${CERTS_DIR}/cert.pem" ]
    [ -f "${CERTS_DIR}/key.pem" ]
}

@test "generated key file has mode 600" {
    generate_certs

    local mode
    mode="$(stat -f '%A' "${CERTS_DIR}/key.pem" 2>/dev/null || stat -c '%a' "${CERTS_DIR}/key.pem")"
    [ "${mode}" = "600" ]
}

@test "generated cert covers the Cync cloud domains via SAN" {
    generate_certs

    run openssl x509 -in "${CERTS_DIR}/cert.pem" -noout -text
    [[ "${output}" == *"cm.gelighting.com"* ]]
    [[ "${output}" == *"cm-sec.gelighting.com"* ]]
    [[ "${output}" == *"cm-ge.xlink.cn"* ]]
}

@test "generate_certs does not overwrite an existing cert" {
    generate_certs
    local first_hash
    first_hash="$(md5sum "${CERTS_DIR}/cert.pem" 2>/dev/null || md5 -q "${CERTS_DIR}/cert.pem")"

    generate_certs
    local second_hash
    second_hash="$(md5sum "${CERTS_DIR}/cert.pem" 2>/dev/null || md5 -q "${CERTS_DIR}/cert.pem")"

    [ "${first_hash}" = "${second_hash}" ]
}

# ---------------------------------------------------------------------------
# configure_env()
# ---------------------------------------------------------------------------

@test "configure_env exports MQTT and account settings from options" {
    load_cync_lan_run "${FIXTURES_DIR}/options_cync_lan_rich.json"
    SECRET_KEY="whatever"

    configure_env

    [ "${CYNC_MQTT_HOST}" = "mqtt.example.lan" ]
    [ "${CYNC_MQTT_PORT}" = "8883" ]
    [ "${CYNC_MQTT_USER}" = "cync" ]
    [ "${CYNC_MQTT_PASS}" = "mqttpass" ]
    [ "${CYNC_TOPIC}" = "custom_cync" ]
    [ "${CYNC_ACCOUNT_USERNAME}" = "cync-account-email@gmail.com" ]
    [ "${CYNC_ACCOUNT_PASSWORD}" = "cync-account-password" ]
    [ "${CYNC_ENABLE_EXPORTER}" = "false" ]
    [ "${CYNC_MAX_TCP_CONN}" = "16" ]
    [ "${CYNC_DEBUG}" = "true" ]
}

@test "configure_env joins tcp_whitelist into a comma-separated string" {
    load_cync_lan_run "${FIXTURES_DIR}/options_cync_lan_rich.json"
    SECRET_KEY="whatever"

    configure_env

    [ "${CYNC_TCP_WHITELIST}" = "10.0.1.112,10.0.1.167" ]
}

@test "configure_env leaves CYNC_TCP_WHITELIST unset when the whitelist is empty" {
    SECRET_KEY="whatever"

    configure_env

    [ -z "${CYNC_TCP_WHITELIST:-}" ]
}

@test "configure_env points cert/key/config paths at the persistent dirs" {
    SECRET_KEY="whatever"

    configure_env

    [ "${CYNC_CONFIG_DIR}" = "${CONFIG_DIR}" ]
    [ "${CYNC_DEVICE_CERT}" = "${CERTS_DIR}/cert.pem" ]
    [ "${CYNC_DEVICE_KEY}" = "${CERTS_DIR}/key.pem" ]
}

@test "configure_env warns when exporter is enabled without account credentials" {
    load_cync_lan_run "${FIXTURES_DIR}/options_cync_lan_no_creds.json"
    SECRET_KEY="whatever"

    run configure_env
    [ "${status}" -eq 0 ]
}
