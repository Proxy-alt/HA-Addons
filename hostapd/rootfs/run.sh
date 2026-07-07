#!/bin/bash
# shellcheck disable=SC1091
set -euo pipefail

source "${BASHIO_LIB:-/usr/lib/bashio/bashio.sh}"

OPTIONS="${OPTIONS:-/data/options.json}"
CONFIG_FILE="${CONFIG_FILE:-/data/hostapd.conf}"
HOSTAPD_BIN="${HOSTAPD_BIN:-/usr/sbin/hostapd}"

RADIUS_REQUIRED=false

# Uses select(. != null) so that boolean false is returned as "false" rather
# than being silently discarded by jq's // empty alternative operator.
opt() { jq -r --arg k "$1" '.[$k] | select(. != null)' "${OPTIONS}"; }

# Reads a scalar field nested under the top-level "radius" object.
radius_opt() { jq -r --arg k "$1" '.radius[$k] | select(. != null)' "${OPTIONS}"; }

# ---------------------------------------------------------------------------
# Unblock the Wi-Fi radio if it's soft-blocked (common on first boot / after
# an OS update re-applies a default rfkill policy).
# ---------------------------------------------------------------------------
unblock_wifi() {
    if command -v rfkill >/dev/null 2>&1; then
        rfkill unblock wifi 2>/dev/null || bashio::log.warning "Could not unblock Wi-Fi radio via rfkill."
    fi
}

# ---------------------------------------------------------------------------
# Radio-wide (non-per-BSS) settings, written once at the top of the file.
# ---------------------------------------------------------------------------
write_radio_block() {
    local interface hw_mode channel country ieee80211d ieee80211h
    local ieee80211n ieee80211ac ieee80211ax ht_capab vht_capab
    local wmm_enabled beacon_int dtim_period max_num_sta rts_threshold fragm_threshold

    interface="$(opt interface)"
    hw_mode="$(opt hw_mode)"
    channel="$(opt channel)"
    country="$(opt country_code)"
    ieee80211d="$(opt ieee80211d)"
    ieee80211h="$(opt ieee80211h)"
    ieee80211n="$(opt ieee80211n)"
    ieee80211ac="$(opt ieee80211ac)"
    ieee80211ax="$(opt ieee80211ax)"
    ht_capab="$(opt ht_capab)"
    vht_capab="$(opt vht_capab)"
    wmm_enabled="$(opt wmm_enabled)"
    beacon_int="$(opt beacon_int)"
    dtim_period="$(opt dtim_period)"
    max_num_sta="$(opt max_num_sta)"
    rts_threshold="$(opt rts_threshold)"
    fragm_threshold="$(opt fragm_threshold)"

    printf 'interface=%s\n' "${interface}"
    printf 'driver=nl80211\n'
    printf 'hw_mode=%s\n' "${hw_mode}"
    printf 'channel=%s\n' "${channel}"
    printf 'country_code=%s\n' "${country}"
    printf 'beacon_int=%s\n' "${beacon_int}"
    printf 'dtim_period=%s\n' "${dtim_period}"

    [[ "${ieee80211d}" == "true" ]] && printf 'ieee80211d=1\n'
    [[ "${ieee80211h}" == "true" ]] && printf 'ieee80211h=1\n'
    [[ "${ieee80211n}" == "true" ]] && printf 'ieee80211n=1\n'
    [[ "${ieee80211ac}" == "true" ]] && printf 'ieee80211ac=1\n'
    [[ "${ieee80211ax}" == "true" ]] && printf 'ieee80211ax=1\n'
    [[ -n "${ht_capab}" ]] && printf 'ht_capab=%s\n' "${ht_capab}"
    [[ -n "${vht_capab}" ]] && printf 'vht_capab=%s\n' "${vht_capab}"

    printf 'wmm_enabled=%s\n' "$([[ "${wmm_enabled}" == "true" ]] && echo 1 || echo 0)"
    [[ "${max_num_sta}" != "0" ]] && printf 'max_num_sta=%s\n' "${max_num_sta}"
    [[ "${rts_threshold}" != "-1" ]] && printf 'rts_threshold=%s\n' "${rts_threshold}"
    [[ "${fragm_threshold}" != "-1" ]] && printf 'fragm_threshold=%s\n' "${fragm_threshold}"

    printf 'macaddr_acl=0\n'
    printf 'auth_algs=1\n'
}

# ---------------------------------------------------------------------------
# RADIUS client lines, written into every Enterprise-mode BSS block.
# ---------------------------------------------------------------------------
write_radius_lines() {
    local nas_identifier own_ip auth_addr auth_port auth_secret
    local acct_enabled acct_addr acct_port acct_secret

    nas_identifier="$(radius_opt nas_identifier)"
    own_ip="$(radius_opt own_ip_addr)"
    auth_addr="$(radius_opt auth_server_addr)"
    auth_port="$(radius_opt auth_server_port)"
    auth_secret="$(radius_opt auth_server_secret)"
    acct_enabled="$(radius_opt acct_enabled)"
    acct_addr="$(radius_opt acct_server_addr)"
    acct_port="$(radius_opt acct_server_port)"
    acct_secret="$(radius_opt acct_server_secret)"

    [[ -n "${nas_identifier}" ]] && printf 'nas_identifier=%s\n' "${nas_identifier}"
    [[ -n "${own_ip}" ]] && printf 'own_ip_addr=%s\n' "${own_ip}"
    printf 'auth_server_addr=%s\n' "${auth_addr}"
    printf 'auth_server_port=%s\n' "${auth_port}"
    printf 'auth_server_shared_secret=%s\n' "${auth_secret}"

    if [[ "${acct_enabled}" == "true" ]]; then
        printf 'acct_server_addr=%s\n' "${acct_addr}"
        printf 'acct_server_port=%s\n' "${acct_port}"
        printf 'acct_server_shared_secret=%s\n' "${acct_secret}"
    fi
}

# ---------------------------------------------------------------------------
# Security-mode-specific lines for a single access point. PMF (ieee80211w) is
# derived from the mode rather than exposed as a separate option, since WPA3
# and OWE mandate it and getting it wrong silently breaks the spec guarantee.
# ---------------------------------------------------------------------------
write_security_block() {
    local mode="$1" passphrase="$2"

    case "${mode}" in
        open)
            printf 'ieee80211w=0\n'
            ;;
        owe)
            printf 'wpa=2\n'
            printf 'wpa_key_mgmt=OWE\n'
            printf 'rsn_pairwise=CCMP\n'
            printf 'ieee80211w=2\n'
            ;;
        wpa2_personal)
            printf 'wpa=2\n'
            printf 'wpa_key_mgmt=WPA-PSK\n'
            printf 'rsn_pairwise=CCMP\n'
            printf 'wpa_passphrase=%s\n' "${passphrase}"
            printf 'ieee80211w=1\n'
            ;;
        wpa3_personal)
            printf 'wpa=2\n'
            printf 'wpa_key_mgmt=SAE\n'
            printf 'rsn_pairwise=CCMP\n'
            printf 'wpa_passphrase=%s\n' "${passphrase}"
            printf 'ieee80211w=2\n'
            printf 'sae_require_mfp=1\n'
            ;;
        wpa2_wpa3_personal)
            printf 'wpa=2\n'
            printf 'wpa_key_mgmt=WPA-PSK SAE\n'
            printf 'rsn_pairwise=CCMP\n'
            printf 'wpa_passphrase=%s\n' "${passphrase}"
            printf 'ieee80211w=1\n'
            ;;
        wpa2_enterprise)
            printf 'wpa=2\n'
            printf 'wpa_key_mgmt=WPA-EAP\n'
            printf 'rsn_pairwise=CCMP\n'
            printf 'ieee8021x=1\n'
            printf 'ieee80211w=1\n'
            write_radius_lines
            ;;
        wpa3_enterprise)
            printf 'wpa=2\n'
            printf 'wpa_key_mgmt=WPA-EAP-SHA256\n'
            printf 'rsn_pairwise=CCMP\n'
            printf 'ieee8021x=1\n'
            printf 'ieee80211w=2\n'
            write_radius_lines
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Validate one access point entry. Returns non-zero (without printing a
# partial config) if the entry is unusable.
# ---------------------------------------------------------------------------
validate_access_point() {
    local ssid="$1" mode="$2" passphrase="$3"

    if [[ -z "${ssid}" ]]; then
        bashio::log.fatal "An access point is missing an ssid. Refusing to start."
        return 1
    fi

    case "${mode}" in
        open|owe)
            [[ -n "${passphrase}" ]] && bashio::log.warning "SSID '${ssid}': wpa_passphrase is ignored for security_mode '${mode}'."
            [[ "${mode}" == "open" ]] && bashio::log.warning "SSID '${ssid}' is an OPEN network with no encryption."
            ;;
        wpa2_personal|wpa3_personal|wpa2_wpa3_personal)
            if [[ -z "${passphrase}" ]] || [[ "${#passphrase}" -lt 8 ]] || [[ "${#passphrase}" -gt 63 ]]; then
                bashio::log.fatal "SSID '${ssid}': wpa_passphrase must be 8-63 characters for security_mode '${mode}' (got ${#passphrase}). Refusing to start."
                return 1
            fi
            ;;
        wpa2_enterprise|wpa3_enterprise)
            RADIUS_REQUIRED=true
            ;;
        *)
            bashio::log.fatal "SSID '${ssid}': unknown security_mode '${mode}'. Refusing to start."
            return 1
            ;;
    esac

    return 0
}

# ---------------------------------------------------------------------------
# Validate the shared RADIUS config, only required when at least one access
# point uses an Enterprise security mode.
# ---------------------------------------------------------------------------
validate_radius() {
    [[ "${RADIUS_REQUIRED}" == "true" ]] || return 0

    if [[ "$(radius_opt enabled)" != "true" ]]; then
        bashio::log.fatal "An access point uses an Enterprise security_mode but radius.enabled is false. Refusing to start."
        return 1
    fi

    if [[ -z "$(radius_opt auth_server_addr)" ]] || [[ -z "$(radius_opt auth_server_secret)" ]] || [[ -z "$(radius_opt own_ip_addr)" ]]; then
        bashio::log.fatal "radius.auth_server_addr, radius.auth_server_secret, and radius.own_ip_addr are all required when an Enterprise access point is configured. Refusing to start."
        return 1
    fi

    if [[ "$(radius_opt acct_enabled)" == "true" ]] && { [[ -z "$(radius_opt acct_server_addr)" ]] || [[ -z "$(radius_opt acct_server_secret)" ]]; }; then
        bashio::log.fatal "radius.acct_enabled is true but radius.acct_server_addr/acct_server_secret are not both set. Refusing to start."
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Write hostapd.conf from add-on options: one radio block followed by one
# BSS block per configured access point (hostapd's multi-BSS support puts
# every extra SSID after the first on a virtual "<interface>_N" interface).
# ---------------------------------------------------------------------------
write_hostapd_config() {
    local interface ap_count=0 ssid mode passphrase hide_ssid ap_json

    interface="$(opt interface)"

    if [[ "$(jq '.access_points | length' "${OPTIONS}")" -eq 0 ]]; then
        bashio::log.fatal "No access points configured. Add at least one entry to access_points. Refusing to start."
        return 1
    fi

    while IFS= read -r ap_json; do
        ssid="$(jq -r '.ssid | select(. != null)' <<<"${ap_json}")"
        mode="$(jq -r '.security_mode | select(. != null)' <<<"${ap_json}")"
        passphrase="$(jq -r '.wpa_passphrase | select(. != null)' <<<"${ap_json}")"
        # Explicit check (not relying on set -e) since a failure here happens
        # inside a loop body, and callers running this under a wrapper that
        # disables errexit (e.g. bats' `run`) would otherwise silently
        # continue past a failed validation.
        validate_access_point "${ssid}" "${mode}" "${passphrase}" || return 1
    done < <(jq -c '.access_points[]' "${OPTIONS}")

    validate_radius || return 1

    bashio::log.info "Writing hostapd configuration for interface ${interface}..."

    {
        write_radio_block

        ap_count=0
        while IFS= read -r ap_json; do
            ssid="$(jq -r '.ssid' <<<"${ap_json}")"
            mode="$(jq -r '.security_mode' <<<"${ap_json}")"
            passphrase="$(jq -r '.wpa_passphrase | select(. != null)' <<<"${ap_json}")"
            hide_ssid="$(jq -r '.hide_ssid | select(. != null)' <<<"${ap_json}")"

            printf '\n'
            if [[ "${ap_count}" -gt 0 ]]; then
                printf 'bss=%s_%s\n' "${interface}" "${ap_count}"
            fi
            printf 'ssid=%s\n' "${ssid}"
            [[ "${hide_ssid}" == "true" ]] && printf 'ignore_broadcast_ssid=1\n'
            write_security_block "${mode}" "${passphrase}"

            ap_count=$((ap_count + 1))
        done < <(jq -c '.access_points[]' "${OPTIONS}")
    } > "${CONFIG_FILE}"
}

main() {
    unblock_wifi
    write_hostapd_config

    bashio::log.info "Starting hostapd on $(opt interface)..."
    exec "${HOSTAPD_BIN}" "${CONFIG_FILE}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi
