## 1.0.0

### Added

- Initial release.
- [FreeRADIUS](https://freeradius.org/) server for WPA2/WPA3-Enterprise
  Wi-Fi (802.1X) and other RADIUS-authenticated services, installed from
  the Debian package repos.
- Configurable NAS clients (`clients`) and local users (`users`) from the
  Home Assistant UI.
- Configurable default EAP method (PEAP/TTLS/TLS) and client-certificate
  requirement.
- Self-signed CA and server certificate generated on first run and
  persisted to `/data/certs`, used for the EAP-TLS/PEAP/TTLS TLS tunnel.
- Designed to pair with this repository's Hostapd add-on's Enterprise
  access points.
- Support for **amd64** and **aarch64** architectures.
