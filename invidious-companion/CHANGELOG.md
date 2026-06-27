## 2024.12.0

### Added

- Initial release.
- Pulls the official
  [Invidious Companion](https://github.com/iv-org/invidious-companion) binary
  directly from the upstream image (`quay.io/invidious/invidious-companion:latest`)
  so the add-on always ships an unmodified build.
- Reads Companion Key, download threads, and proxy settings from the
  Home Assistant add-on configuration UI — no manual config file editing required.
- Companion Key is validated at startup; the add-on exits with a clear fatal-log
  message if it is missing or blank.
- `BACKEND_VIDEO_DOWNLOAD_THREADS` wired to the **Download Threads** option
  so parallel stream fetch count is configurable without SSH access.
- Support for HTTP/HTTPS outbound proxies via the **HTTP Proxy URL** option;
  sets both `HTTP_PROXY` and `http_proxy` environment variables for broad
  compatibility.
- Support for SOCKS4/5 outbound proxies via **SOCKS Proxy Host** and
  **SOCKS Proxy Port** options.
- Companion listens on port **8282**, mapped to the host by default so
  Invidious can reach it at `http://<ha-ip>:8282`.
- Support for **amd64** and **aarch64** architectures.
