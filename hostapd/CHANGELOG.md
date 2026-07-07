## 2.0.0

### Added

- Multiple access points (`access_points` list) broadcast simultaneously
  from one radio via hostapd's multi-BSS support, each with its own SSID
  and independent security mode.
- Per-access-point `security_mode`: `open`, `owe` (WPA3 Enhanced Open),
  `wpa2_personal`, `wpa3_personal` (SAE), `wpa2_wpa3_personal` (transition),
  `wpa2_enterprise`, and `wpa3_enterprise` (802.1X via RADIUS). Protected
  Management Frames (`ieee80211w`) are derived automatically per mode.
- `radius` configuration block for pointing Enterprise-mode access points at
  an external RADIUS server (e.g. this repository's new FreeRADIUS add-on),
  including optional RADIUS accounting.
- Expanded radio options: `ieee80211ac`/`ieee80211ax` (Wi-Fi 5/6),
  `ieee80211h` (DFS/TPC), `ht_capab`/`vht_capab` (advanced capability
  strings), `wmm_enabled`, `beacon_int`, `dtim_period`, `max_num_sta`,
  `rts_threshold`, `fragm_threshold`, and `channel: 0` for automatic channel
  selection (ACS).

### Changed

- **Breaking**: `ssid`, `wpa_passphrase`, and `hide_ssid` moved from
  top-level options into entries of the new `access_points` list.

## 1.0.0

### Added

- Initial release.
- Turns a host Wi-Fi interface into a wireless access point using
  [hostapd](https://w1.fi/hostapd/), installed from the Debian package repos.
- Configurable SSID, WPA2 passphrase, band, channel, and country code from the
  Home Assistant UI.
- Unblocks a soft-blocked Wi-Fi radio via `rfkill` on start.
- Refuses to start if a configured passphrase is outside the WPA2 8-63
  character range.
- Requires `host_network`, the `NET_ADMIN`/`NET_RAW` capabilities, `/dev/rfkill`,
  and disabled AppArmor — see DOCS.md for why each is needed.
- Support for **amd64** and **aarch64** architectures.
