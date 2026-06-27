# Invidious — Home Assistant Add-on Repository

A Home Assistant OS add-on that runs [Invidious](https://github.com/iv-org/invidious),
a privacy-respecting alternative front-end to YouTube.

Watch YouTube videos without ads, tracking, or a Google account — directly from
your Home Assistant instance.

## Installation

1. In Home Assistant, go to **Settings → Add-ons → Add-on Store**.
2. Click the **⋮** menu (top-right) and choose **Repositories**.
3. Paste the URL of this repository and click **Add**.
4. Find **Invidious** in the store and click **Install**.
5. Click **Start**. The add-on appears in your sidebar automatically.

## Add-ons in this repository

| Add-on | Description |
|---|---|
| [Invidious](invidious/) | Privacy-respecting YouTube frontend with bundled PostgreSQL |

## Features

- **Self-contained** — includes its own PostgreSQL database; no other add-on required.
- **HA Ingress** — accessible from the HA sidebar without opening extra ports.
- **Full configuration** — all 70+ Invidious config options exposed in the UI.
- **Persistent data** — database and configuration survive restarts and updates.
- **Multi-arch** — supports `amd64` and `aarch64`.

## Support

See the [add-on documentation](invidious/DOCS.md) for setup instructions and
configuration reference.

Issues can be filed in this repository's issue tracker.
