# Home Assistant Community Add-ons

A collection of self-hosted services packaged as [Home Assistant OS](https://www.home-assistant.io/)
add-ons — installable directly from the Add-on Store and configurable entirely
from the Home Assistant UI.

## Installation

1. In Home Assistant, go to **Settings → Add-ons → Add-on Store**.
2. Click the **⋮** menu (top-right) and choose **Repositories**.
3. Paste the URL of this repository and click **Add**.
4. Find the add-on you want in the store and click **Install**, then **Start**.

## Add-ons in this repository

| Add-on | Description |
|---|---|
| [Invidious](invidious/) | Privacy-respecting YouTube frontend with bundled PostgreSQL |
| [Invidious Companion](invidious-companion/) | Video-stream offloader that reduces YouTube rate-limiting for Invidious |
| [Fabric Server](fabric-server/) | Minecraft Fabric server with Geyser + Floodgate (Bedrock cross-play) and performance mods |

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
