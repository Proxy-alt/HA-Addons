## 1.1.2

### Added

- Fix ViaFabric schema validation
- Add ViaFabric tests

## 1.1.1

### Added

- **ViaFabric** support — viafabric, viabackwards, viarewind

## 1.1.0

### Added

- **Two-way config sync for operators and the whitelist.** In-game `/op`,
  `/deop`, `/whitelist add`, and `/whitelist remove` commands are now merged back
  into the add-on options via the Supervisor API, so the UI reflects changes made
  at runtime instead of overwriting them on restart.
- **Whitelisted Players** option — manage whitelist membership from the UI
  (resolved to UUIDs and written to `whitelist.json`).

## 1.0.0

### Added

- Initial release.
- Runs a [Fabric](https://fabricmc.net/) Minecraft server on Eclipse Temurin
  (LTS JRE), built on the Home Assistant Debian base image.
- Resolves Minecraft and Fabric loader versions dynamically from the Fabric meta
  API; set either to `latest` or pin a specific version.
- Downloads the Fabric server launcher on demand and caches it until the
  resolved version changes.
- Installs mods from [Modrinth](https://modrinth.com/), always picking the newest
  Fabric build that matches the resolved Minecraft version. Mods without a
  matching build are skipped with a warning instead of failing the start.
- **Bedrock cross-play** via [Geyser](https://geysermc.org/) and
  [Floodgate](https://wiki.geysermc.org/floodgate/); Floodgate auth is wired up
  automatically when both are enabled.
- Bundled, toggleable optimization mods: **Lithium**, **FerriteCore**,
  **Krypton**, **C2ME**, and **ServerCore**. **Fabric API** is pulled in
  automatically as a dependency.
- **Extra Mods** option to install any additional Modrinth mod by project slug.
- Generates `server.properties` from the UI on every start (MOTD, game mode,
  difficulty, players, online mode, whitelist, distances, world settings, and
  more).
- **Operators** option resolves Java usernames to UUIDs via the Mojang API and
  writes `ops.json`.
- Tuned G1GC ("Aikar's") JVM flags by default, plus an **Extra Java Arguments**
  option.
- Manually added jars in `/data/server/mods` are preserved — only add-on-managed
  mods are replaced on restart.
- Ports: **25565/tcp** (Java) and **19132/udp** (Bedrock).
- Support for **amd64** and **aarch64** architectures.
