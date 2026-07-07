#!/bin/bash
# shellcheck disable=SC1091
set -euo pipefail

source "${BASHIO_LIB:-/usr/lib/bashio/bashio.sh}"

OPTIONS="${OPTIONS:-/data/options.json}"
CONFIG_FILE="${CONFIG_FILE:-/data/hostapd.conf}"
HOSTAPD_BIN="${HOSTAPD_BIN:-/usr/sbin/hostapd}"

# Uses select(. != null) so that boolean false is returned as "false" rather
# than being silently discarded by jq's // empty alternative operator.
opt() { jq -r --arg k "$1" '.[$k] | select(. != null)' "${OPTIONS}"; }

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
# Write hostapd.conf from add-on options.
# ---------------------------------------------------------------------------
write_hostapd_config() {
    local interface ssid passphrase hw_mode channel country ieee80211n hide_ssid

    interface="$(opt interface)"
    ssid="$(opt ssid)"
    passphrase="$(opt wpa_passphrase)"
    hw_mode="$(opt hw_mode)"
    channel="$(opt channel)"
    country="$(opt country_code)"
    ieee80211n="$(opt ieee80211n)"
    hide_ssid="$(opt hide_ssid)"

    if [[ -n "${passphrase}" ]] && { [[ "${#passphrase}" -lt 8 ]] || [[ "${#passphrase}" -gt 63 ]]; }; then
        bashio::log.fatal "wpa_passphrase must be 8-63 characters (got ${#passphrase}). Refusing to start."
        return 1
    fi

    if [[ -z "${passphrase}" ]]; then
        bashio::log.warning "No wpa_passphrase set — starting an OPEN network with no encryption."
    fi

    bashio::log.info "Writing hostapd configuration for interface ${interface}..."

    {
        printf 'interface=%s\n' "${interface}"
        printf 'driver=nl80211\n'
        printf 'ssid=%s\n' "${ssid}"
        printf 'hw_mode=%s\n' "${hw_mode}"
        printf 'channel=%s\n' "${channel}"
        printf 'country_code=%s\n' "${country}"
        printf 'ieee80211d=1\n'
        printf 'wmm_enabled=1\n'
        printf 'macaddr_acl=0\n'
        printf 'auth_algs=1\n'

        [[ "${ieee80211n}" == "true" ]] && printf 'ieee80211n=1\n'
        [[ "${hide_ssid}" == "true" ]] && printf 'ignore_broadcast_ssid=1\n'

        if [[ -n "${passphrase}" ]]; then
            printf 'wpa=2\n'
            printf 'wpa_key_mgmt=WPA-PSK\n'
            printf 'rsn_pairwise=CCMP\n'
            printf 'wpa_passphrase=%s\n' "${passphrase}"
        fi
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
