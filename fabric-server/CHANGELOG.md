## 2.0.0

### Added

- **Multi-server-type support.** Choose from **Vanilla**, **Paper**, **Purpur**,
  **Fabric** (default), **Forge**, **Bedrock Dedicated Server (BDS)**, or
  **EaglercraftX** via the new `server_type` option. Each type has its own
  startup logic and a dedicated run script (`/servers/run_*.sh`).
- **Web dashboard with HASS ingress.** A built-in Python/aiohttp dashboard is
  accessible directly from the Home Assistant sidebar. It shows
  server type, Minecraft version, player count, uptime, and live server status.
- **Live console terminal in the dashboard.** The browser UI streams the server
  log in real time and lets you send commands via an input bar — no SSH needed.
- **Forge support.** Downloads the Forge installer for the chosen Minecraft
  version, runs it server-side, and launches via the generated `run.sh` (1.17+)
  or the server JAR (pre-1.17).
- **Paper support.** Downloads the latest stable Paper build from the PaperMC
  API for the configured Minecraft version.
- **Purpur support.** Downloads from the Purpur API; compatible with Paper/
  Spigot plugins.
- **Vanilla support.** Downloads the official Mojang server JAR via the version
  manifest; no mods, maximum compatibility.
- **Bedrock Dedicated Server (BDS) support.** Downloads from the Minecraft
  website and launches the native binary. Bedrock clients only; no Java needed.
  BDS allow-list and permissions files are generated from the ops/whitelist
  options. Note: XUIDs are not auto-resolved.
- **EaglercraftX support.** Place the EaglercraftX server JAR at
  `/share/mc_server/eaglercraft-server.jar` and select `eaglercraft` as the
  server type.
- **`forge_version` option.** Set to `"latest"` (default, picks the recommended
  build), `"recommended"`, or a specific version string like `"54.1.0"`.
- The add-on is renamed from "Fabric Server" to **"Minecraft Server"** in the
  UI. The slug (`fabric_server`) is unchanged for upgrade compatibility.

### Changed

- Server scripts are now split: `run.sh` is a thin dispatcher; shared helpers
  live in `/servers/common.sh`; each server type has its own `/servers/run_*.sh`.
- Server JARs (non-Fabric) are cached under `/data/<type>/` so switching between
  types doesn't re-download on every restart.

### Notes

- Geyser, Floodgate, and ViaVersion/ViaBackwards/ViaRewind are now managed
  automatically across **Fabric, Paper, Purpur, and Forge** — each platform
  gets the correct build fetched directly from Modrinth (ViaFabric on Fabric,
  ViaVersion on Paper/Purpur, ViaForge on Forge). The Fabric-only optimization
  mods (Lithium, FerriteCore, Krypton, C2ME, ServerCore) have no equivalent on
  other loaders and are skipped with a log warning. Vanilla, BDS, and
  EaglercraftX have no managed mods/plugins at all — see their server-type
  notes in the configuration UI.
- Spigot is not supported via auto-download (BuildTools requires source
  compilation). Use **Paper** or **Purpur** as drop-in replacements.

## 1.2.0

### Added

- The Minecraft world is now stored in the add-on **config folder**
  (`/addon_configs/<slug>`), browsable via the File editor / Samba add-ons, so
  you can back up, edit, or drop in your own world. Existing worlds under
  `/data/server` are migrated automatically.

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
