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
