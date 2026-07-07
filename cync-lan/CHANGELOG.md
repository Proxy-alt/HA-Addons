## 1.0.0

### Added

- Initial release, wrapping [cync-lan](https://github.com/baudneo/cync-lan)
  (`baudneo/cync-lan`, `python` branch), a local async MQTT bridge for
  Cync/C by GE Wi-Fi smart lighting.
- Generates a per-install self-signed TLS certificate for device connections
  on first start, persisted to `/data/certs`.
- Auto-generates and persists a secret key (used to encrypt the cached Cync
  cloud auth token) the same way the Invidious add-on handles its HMAC key.
- Configurable Cync account credentials, MQTT broker connection, device
  connection cap, and an optional device IP whitelist from the Home
  Assistant UI.
- Requires `host_network` so the add-on is reachable on the same LAN address
  that DNS overrides for `cm.gelighting.com` / `cm-sec.gelighting.com` /
  `cm-ge.xlink.cn` need to point at — see DOCS.md.
- Support for **amd64** and **aarch64** architectures.
