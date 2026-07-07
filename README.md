# Home Assistant Community Add-ons
[![Open your Home Assistant instance and show the add app repository dialog with a specific repository URL pre-filled.](https://my.home-assistant.io/badges/supervisor_add_addon_repository.svg)](https://my.home-assistant.io/redirect/supervisor_add_addon_repository/?repository_url=https%3A%2F%2Fgithub.com%2FProxy-alt%2FHA-Addons%2F)


A collection of self-hosted services packaged as [Home Assistant OS](https://www.home-assistant.io/)
add-ons — installable directly from the Add-on Store and configurable entirely
from the Home Assistant UI.

## Installation

1. In Home Assistant, go to **Settings → Add-ons → Add-on Store**.
2. Click the **⋮** menu (top-right) and choose **Repositories**.
3. Paste the URL of this repository and click **Add**.
4. Find the add-on you want in the store and click **Install**, then **Start**.

## Add-ons in this repository

| Add-on                                      | Description                                                                                                                                                |
|---------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------|
| [Invidious](invidious/)                     | Privacy-respecting YouTube frontend with bundled PostgreSQL                                                                                                |
| [Invidious Companion](invidious-companion/) | Video-stream offloader that reduces YouTube rate-limiting for Invidious                                                                                    |
| [Minecraft Server](fabric-server/)          | Minecraft server with Geyser + Floodgate (Bedrock cross-play), supports choosing Bedrock Dedicated Server (BDS), Vanilla, Fabric, Paper, PurPur, and Forge |
| [Hostapd](hostapd/)                         | Turns a Wi-Fi interface into a wireless access point                                                                                                        |
| [Cync LAN](cync-lan/)                       | Local, cloud-free MQTT bridge for GE Cync / C by GE Wi-Fi smart lighting                                                                                    |

## What these add-ons share

- **UI-driven configuration** — every option is exposed in the add-on
  configuration page; no SSH or manual file editing required.
- **Persistent data** — worlds, databases, and configuration survive restarts
  and updates.
- **Multi-arch** — `amd64` and `aarch64` are supported.
- **Upstream binaries** — where possible, official upstream artifacts are used
  unmodified so the add-ons stay close to upstream releases.

## Support

Each add-on ships its own `DOCS.md` with setup and configuration reference.
Issues can be filed in this repository's issue tracker.
