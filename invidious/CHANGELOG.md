## 2024.12.2

### Fixed

- Preference changes made by administrators on the Invidious `/preferences` page
  (which Invidious saves to `config.yml`) now persist across restarts. The
  generated config is stored on the `/data` volume and is only regenerated when
  the add-on options actually change, so admin web-UI changes are no longer
  overwritten on every start.

## 2024.12.1

### Added

- The auto-generated HMAC key is now written back to the add-on options via the
  Supervisor API, so it is visible in the UI and reused as the canonical key.

## 2024.12.0

### Added

- Initial release.
- Bundled PostgreSQL — no external database add-on required.
- Full coverage of all Invidious configuration options (70 options across
  server, networking, logging, users, background jobs, Invidious Companion,
  and default user preferences).
- Home Assistant Ingress support — access Invidious directly from the
  HA sidebar without opening an extra port.
- HMAC key auto-generated and persisted on first run if left blank.
- Support for amd64 and aarch64 architectures.
