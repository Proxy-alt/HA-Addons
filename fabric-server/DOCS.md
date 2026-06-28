# Fabric Server — Add-on Documentation

Runs a [Fabric](https://fabricmc.net/) Minecraft server with optional
[Geyser](https://geysermc.org/) + [Floodgate](https://wiki.geysermc.org/floodgate/)
for Bedrock cross-play and a curated set of performance mods — all configured
from the Home Assistant UI. No SSH or manual file editing required.

---

## Quick start

1. Install and open the add-on's **Configuration** tab.
2. Set **Accept Minecraft EULA** to `true` (required — see
   <https://aka.ms/MinecraftEULA>).
3. Adjust **Maximum Memory** to suit your hardware (e.g. `2G`).
4. **Save**, then **Start** the add-on.
5. Connect from Java Edition at `your-ha-host:25565`. Bedrock clients connect to
   the same host on UDP port `19132`.

> **First start takes a while.** The add-on downloads the Fabric server
> launcher, the Minecraft server, Fabric libraries, and the enabled mods, then
> generates the world. Watch the **Log** tab for progress.

---

## How it works

On every start the add-on:

1. Resolves the Minecraft / Fabric versions (`latest` → newest stable via the
   Fabric meta API).
2. Downloads the Fabric **server launcher** for that version (cached until the
   version changes).
3. Synchronises mods — it removes the mods it previously installed, then
   downloads the currently enabled set from [Modrinth](https://modrinth.com/),
   picking the newest Fabric build that matches your Minecraft version. Any mod
   without a matching build is **skipped with a warning**, never a crash.
4. Syncs in-game changes (operators and whitelist) made with commands during the
   previous session back into the add-on options (see [Two-way config
   sync](#two-way-config-sync)).
5. Regenerates `server.properties`, the Geyser config, `ops.json`, and
   `whitelist.json` from your options.
6. Launches the server with tuned G1GC ("Aikar's") JVM flags.

All server data lives under the add-on's persistent `/data/server` directory, so
worlds and configuration survive restarts and updates.

---

## Versions

| Option | Notes |
|---|---|
| **Minecraft Version** | A specific version like `1.21.4`, or `latest`. |
| **Fabric Loader Version** | A specific loader, or `latest` (recommended). |

> **The newest Minecraft version often lacks mod support.** Right after a
> Minecraft release, Geyser and some optimization mods may not have a compatible
> build yet. If Bedrock cross-play or a mod you need is being skipped in the log,
> pin **Minecraft Version** to a slightly older release that has full support.

---

## Memory

| Option | Meaning |
|---|---|
| **Maximum Memory** | `-Xmx` Java heap cap, e.g. `2G`, `2048M`. |
| **Minimum Memory** | `-Xms` initial heap, e.g. `1G`. |
| **Extra Java Arguments** | Appended after the built-in tuning flags. |

Leave RAM headroom for Home Assistant itself and any other add-ons. A good rule
of thumb is to give the server no more than half of the host's total memory.

---

## Server properties

The following are exposed directly and written to `server.properties` on each
start: MOTD, game mode, difficulty, hardcore, max players, online mode,
whitelist, PvP, allow-nether, allow-flight, spawn protection, view/simulation
distance, world name, world seed, world type, command blocks, operator
permission level, and idle timeout.

> Because `server.properties` is regenerated from the add-on options every
> start, edit settings here rather than in the file.

### Operators

List Java usernames under **Operators**. At startup each name is resolved to a
UUID via the Mojang API and written to `ops.json` with your configured
**Operator Permission Level**. Names that cannot be resolved (typos, API
hiccups) are skipped with a warning.

### Whitelist

Set **Whitelist** to `true` to restrict access to whitelisted players, and list
the allowed Java usernames under **Whitelisted Players**. Each name is resolved
to a UUID via the Mojang API and written to `whitelist.json` at startup.

---

## Two-way config sync

Operators and the whitelist can be changed two ways: from the Home Assistant UI
(the **Operators** / **Whitelisted Players** options) and in-game with commands
such as `/op`, `/deop`, `/whitelist add`, and `/whitelist remove`. Normally the
in-game changes would be lost, because the add-on regenerates `ops.json` and
`whitelist.json` from the options on every start.

To prevent that, on each start the add-on performs a **three-way merge** between
the live server files, the add-on options, and the last set it synced:

- Players you `/op` or `/whitelist add` in-game are **added** to the matching
  add-on option, so they show up in the UI.
- Players you `/deop` or `/whitelist remove` in-game are **removed** from the
  option.
- Additions and removals you make in the UI are applied as well.

The merged result is written back to the add-on configuration through the
Supervisor API, so the UI always reflects the current state of the server.

> This requires the add-on's `hassio_api` access (enabled by default). If the
> Supervisor API is unreachable, the merge still applies for the current run and
> a warning is logged; the options simply aren't updated in the UI.

---

## Bedrock cross-play (Geyser + Floodgate)

Enable **Geyser** to let Bedrock Edition clients (mobile, console, Windows
10/11) join this Java server. Bedrock players connect on the **Bedrock Port**
(UDP `19132` by default).

Enable **Floodgate** as well so Bedrock players can join **without owning a Java
account**. Because Geyser and Floodgate run inside the same server here, they
share authentication automatically — no key copying is required, and Geyser's
auth type is set to `floodgate` for you.

> Keep **Online Mode** enabled. Java players are verified against Mojang;
> Bedrock players are handled by Floodgate independently.

If you run Geyser without Floodgate, Bedrock players must link a Java account via
Geyser's authentication flow.

---

## Optimization mods

Toggle any of the bundled, behaviour-preserving performance mods:

| Mod | What it does |
|---|---|
| **Lithium** | General server optimization, no gameplay changes. |
| **FerriteCore** | Lowers memory usage. |
| **Krypton** | Optimizes networking. |
| **C2ME** | Parallelizes chunk loading/generation/saving (great on multi-core). |
| **ServerCore** | Dynamic tick-rate optimizations. |

[Fabric API](https://modrinth.com/mod/fabric-api) is installed automatically
whenever any mod (including Geyser/Floodgate) is enabled, since nearly every
Fabric mod depends on it.

### Extra mods

Add any other [Modrinth](https://modrinth.com/) mod by its **project slug** (the
last segment of its Modrinth URL — e.g. `carpet` for
`https://modrinth.com/mod/carpet`) under **Extra Mods**. The newest Fabric build
matching your Minecraft version is downloaded for each.

> You can also drop `.jar` files directly into `/data/server/mods` (for example
> via the Samba or SSH add-on). The add-on only removes mods **it** installed, so
> manually added jars are left untouched.

---

## Ports

| Port | Protocol | Purpose |
|---|---|---|
| `25565` | TCP | Minecraft Java Edition |
| `19132` | UDP | Minecraft Bedrock Edition (Geyser) |

The add-on uses host networking, so these ports are reachable on your Home
Assistant host's IP. To expose the server to the internet you must forward these
ports on your router — do so deliberately and keep the whitelist or online mode
in mind.

---

## Troubleshooting

### Add-on exits immediately with a EULA message

Set **Accept Minecraft EULA** to `true` in the configuration and save.

### "No '<mod>' build for Minecraft <version>; skipping."

That mod has no release for your Minecraft version yet. Either wait for the mod
to update, or pin **Minecraft Version** to a release the mod already supports.

### Bedrock players can't connect

1. Confirm **Geyser** is enabled and the log shows it loaded (no skip warning).
2. Make sure clients use UDP port `19132` (the **Bedrock Port**).
3. If connecting from the internet, forward UDP `19132` on your router.

### Server is laggy

- Increase **Maximum Memory** if the host has spare RAM.
- Enable **C2ME** and **Lithium** if not already on.
- Lower **View Distance** / **Simulation Distance**.

### Reset the world

Stop the add-on, change **World Name** to a new value (or delete the old world
folder under `/data/server`), and start again.

---

## Logs

Server output appears in the add-on's **Log** tab. Check there first to confirm
which versions resolved, which mods installed or were skipped, and that the
world finished loading. A healthy start ends with the usual
`Done (…s)! For help, type "help"` line from the Minecraft server.
