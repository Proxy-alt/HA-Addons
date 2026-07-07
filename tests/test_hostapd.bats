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
# Radio config generation
# ---------------------------------------------------------------------------

@test "writes interface, hw_mode, channel, and country_code" {
    write_hostapd_config

    assert_file_contains "interface=wlan0"
    assert_file_contains "hw_mode=g"
    assert_file_contains "channel=6"
    assert_file_contains "country_code=US"
}

@test "driver is always nl80211" {
    write_hostapd_config
    assert_file_contains "driver=nl80211"
}

@test "ieee80211d, wmm_enabled, beacon_int, and dtim_period are written" {
    write_hostapd_config

    assert_file_contains "ieee80211d=1"
    assert_file_contains "wmm_enabled=1"
    assert_file_contains "beacon_int=100"
    assert_file_contains "dtim_period=2"
}

@test "ieee80211n=1 is written when enabled" {
    write_hostapd_config
    assert_file_contains "ieee80211n=1"
}

@test "ieee80211ac and ieee80211ax are written when enabled" {
    OPTIONS="${TEST_TMPDIR}/opts.json"
    jq '.ieee80211ac = true | .ieee80211ax = true' "${FIXTURES_DIR}/options_hostapd_defaults.json" > "${OPTIONS}"

    write_hostapd_config

    assert_file_contains "ieee80211ac=1"
    assert_file_contains "ieee80211ax=1"
}

@test "max_num_sta, rts_threshold, and fragm_threshold are omitted at their disabled defaults" {
    write_hostapd_config

    assert_file_not_contains "max_num_sta="
    assert_file_not_contains "rts_threshold="
    assert_file_not_contains "fragm_threshold="
}

@test "max_num_sta, rts_threshold, and fragm_threshold are written when set" {
    OPTIONS="${TEST_TMPDIR}/opts.json"
    jq '.max_num_sta = 10 | .rts_threshold = 500 | .fragm_threshold = 1000' "${FIXTURES_DIR}/options_hostapd_defaults.json" > "${OPTIONS}"

    write_hostapd_config

    assert_file_contains "max_num_sta=10"
    assert_file_contains "rts_threshold=500"
    assert_file_contains "fragm_threshold=1000"
}

# ---------------------------------------------------------------------------
# Access point / security mode generation
# ---------------------------------------------------------------------------

@test "WPA2-Personal block is written for wpa2_personal" {
    write_hostapd_config

    assert_file_contains "ssid=TestAP"
    assert_file_contains "wpa=2"
    assert_file_contains "wpa_key_mgmt=WPA-PSK"
    assert_file_contains "rsn_pairwise=CCMP"
    assert_file_contains "wpa_passphrase=supersecret1"
    assert_file_contains "ieee80211w=1"
}

@test "no WPA block and open-network warning when security_mode is open" {
    load_hostapd_run "${FIXTURES_DIR}/options_hostapd_open.json"

    write_hostapd_config

    assert_file_not_contains "wpa=2"
    assert_file_not_contains "wpa_passphrase="
    assert_file_contains "ieee80211w=0"
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

@test "OWE block requires PMF and uses wpa_key_mgmt=OWE" {
    load_hostapd_run "${FIXTURES_DIR}/options_hostapd_owe.json"

    write_hostapd_config

    assert_file_contains "wpa_key_mgmt=OWE"
    assert_file_contains "ieee80211w=2"
    assert_file_not_contains "wpa_passphrase="
}

@test "WPA3-Personal (SAE) block requires PMF and sae_require_mfp" {
    load_hostapd_run "${FIXTURES_DIR}/options_hostapd_wpa3_personal.json"

    write_hostapd_config

    assert_file_contains "wpa_key_mgmt=SAE"
    assert_file_contains "wpa_passphrase=supersecret1"
    assert_file_contains "ieee80211w=2"
    assert_file_contains "sae_require_mfp=1"
}

# ---------------------------------------------------------------------------
# Passphrase validation
# ---------------------------------------------------------------------------

@test "refuses to start with a Personal passphrase shorter than 8 characters" {
    load_hostapd_run "${FIXTURES_DIR}/options_hostapd_short_passphrase.json"

    run write_hostapd_config
    [ "${status}" -ne 0 ]
    [ ! -f "${CONFIG_FILE}" ]
}

# ---------------------------------------------------------------------------
# Enterprise / RADIUS
# ---------------------------------------------------------------------------

@test "WPA3-Enterprise block includes ieee8021x and mandatory PMF" {
    load_hostapd_run "${FIXTURES_DIR}/options_hostapd_enterprise.json"

    write_hostapd_config

    assert_file_contains "wpa_key_mgmt=WPA-EAP-SHA256"
    assert_file_contains "ieee8021x=1"
    assert_file_contains "ieee80211w=2"
}

@test "Enterprise block writes RADIUS auth and accounting lines" {
    load_hostapd_run "${FIXTURES_DIR}/options_hostapd_enterprise.json"

    write_hostapd_config

    assert_file_contains "own_ip_addr=192.168.1.10"
    assert_file_contains "auth_server_addr=192.168.1.20"
    assert_file_contains "auth_server_port=1812"
    assert_file_contains "auth_server_shared_secret=radiussecret1"
    assert_file_contains "acct_server_addr=192.168.1.20"
    assert_file_contains "acct_server_shared_secret=acctsecret1"
}

@test "refuses to start an Enterprise access point when radius.enabled is false" {
    load_hostapd_run "${FIXTURES_DIR}/options_hostapd_enterprise_missing_radius.json"

    run write_hostapd_config
    [ "${status}" -ne 0 ]
    [ ! -f "${CONFIG_FILE}" ]
}

# ---------------------------------------------------------------------------
# Multi-BSS (multiple access points)
# ---------------------------------------------------------------------------

@test "additional access points are written as bss=<interface>_N blocks" {
    load_hostapd_run "${FIXTURES_DIR}/options_hostapd_multi_ap.json"

    write_hostapd_config

    assert_file_contains "ssid=PrimaryAP"
    assert_file_contains "bss=wlan0_1"
    assert_file_contains "ssid=OweGuestAP"
    assert_file_contains "bss=wlan0_2"
    assert_file_contains "ssid=EnterpriseAP"
}

@test "first access point does not get a bss= line" {
    load_hostapd_run "${FIXTURES_DIR}/options_hostapd_multi_ap.json"

    write_hostapd_config

    run grep -B2 "ssid=PrimaryAP" "${CONFIG_FILE}"
    [[ "${output}" != *"bss="* ]]
}

@test "refuses to start with an empty access_points list" {
    OPTIONS="${TEST_TMPDIR}/opts.json"
    jq '.access_points = []' "${FIXTURES_DIR}/options_hostapd_defaults.json" > "${OPTIONS}"

    run write_hostapd_config
    [ "${status}" -ne 0 ]
    [ ! -f "${CONFIG_FILE}" ]
}
