## 0.1.1

### Added

- `host_network: true` to the add-on configuration to allow the agent to access the host network. Fixes issue with connecting to the host network.

## 0.1.0

### Added

- Initial release.
- Downloads the official [playit-agent](https://github.com/playit-cloud/playit-program)
  binary from GitHub Releases at build time (statically-linked musl build).
- Reads the agent secret key from the Home Assistant add-on configuration UI.
- On first run with no secret key configured, the agent prints a claim URL
  to the add-on Log tab so the agent can be registered at app.playit.gg.
- Agent config is persisted across restarts under the add-on data volume.
- Support for **amd64** and **aarch64** architectures.
