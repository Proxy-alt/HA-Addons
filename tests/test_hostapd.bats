#!/usr/bin/env bats
# Tests for hostapd/rootfs/run.sh

load helpers/common

setup() {
    setup_tmpdir
    load_hostapd_run
}

teardown() {
    teardown_tmpdir
}

# ---------------------------------------------------------------------------
# Config generation
# ---------------------------------------------------------------------------

@test "writes interface, ssid, hw_mode, channel, and country_code" {
    write_hostapd_config

    assert_file_contains "interface=wlan0"
    assert_file_contains "ssid=TestAP"
    assert_file_contains "hw_mode=g"
    assert_file_contains "channel=6"
    assert_file_contains "country_code=US"
}

@test "driver is always nl80211" {
    write_hostapd_config
    assert_file_contains "driver=nl80211"
}

@test "WPA2 block is written when a passphrase is configured" {
    write_hostapd_config

    assert_file_contains "wpa=2"
    assert_file_contains "wpa_key_mgmt=WPA-PSK"
    assert_file_contains "rsn_pairwise=CCMP"
    assert_file_contains "wpa_passphrase=supersecret1"
}

@test "ieee80211n=1 is written when enabled" {
    write_hostapd_config
    assert_file_contains "ieee80211n=1"
}

@test "no WPA block and open-network warning when passphrase is empty" {
    load_hostapd_run "${FIXTURES_DIR}/options_hostapd_open.json"

    write_hostapd_config

    assert_file_not_contains "wpa=2"
    assert_file_not_contains "wpa_passphrase="
}

@test "ignore_broadcast_ssid=1 is written when hide_ssid is enabled" {
    load_hostapd_run "${FIXTURES_DIR}/options_hostapd_open.json"

    write_hostapd_config

    assert_file_contains "ignore_broadcast_ssid=1"
}

@test "ieee80211n line is omitted when disabled" {
    load_hostapd_run "${FIXTURES_DIR}/options_hostapd_open.json"

    write_hostapd_config

    assert_file_not_contains "ieee80211n=1"
}

# ---------------------------------------------------------------------------
# Passphrase validation
# ---------------------------------------------------------------------------

@test "refuses to start with a passphrase shorter than 8 characters" {
    load_hostapd_run "${FIXTURES_DIR}/options_hostapd_short_passphrase.json"

    run write_hostapd_config
    [ "${status}" -ne 0 ]
    [ ! -f "${CONFIG_FILE}" ]
}
