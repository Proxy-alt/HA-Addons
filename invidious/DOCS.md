# Invidious — Add-on Documentation

Invidious is a privacy-respecting alternative front-end to YouTube. It lets you
watch YouTube videos, manage subscriptions, and browse channels without a Google
account, without ads, and without YouTube tracking you.

---

## Quick start

1. Install the add-on and click **Start**.
2. Open the **Invidious** item in your HA sidebar (added automatically via Ingress).
3. That's it — no required configuration for local use.

The add-on starts its own PostgreSQL database on first run. Everything is stored
under the add-on's `/data` directory and persists across restarts and updates.

---

## Accessing the UI

### Via HA Ingress (recommended for local access)

The add-on panel appears automatically in your HA sidebar under the name
**Invidious**. This is the easiest way to access it — no extra ports or
firewall rules needed.

### Via direct port

Port **3000** is also mapped to the host. You can reach the UI at
`http://<your-ha-ip>:3000` from any device on your network.

You can disable the host port mapping in the **Network** section of the
add-on page if you only want Ingress access.

---

## Key settings to configure

Most options have sensible defaults. The settings below are the ones you are
most likely to want to change.

### HMAC Key

Leave this **blank** — the add-on generates a random 64-character key on first
start and saves it to persistent storage. You only need to set this manually if
you want to copy an existing key from another Invidious instance (for example,
when migrating).

> **Warning:** Changing the HMAC key after users have logged in will invalidate
> all existing sessions and PubSubHub subscriptions.

### Domain

Set this to the fully-qualified domain name where Invidious will be publicly
reachable — for example `invidious.example.com`. This is **required** if you:

- access the instance from outside your home network, or
- use a reverse proxy (nginx, Caddy, Traefik, etc.), or
- enable PubSubHub (`use_pubsub_feeds`).

Leave it blank if you only access the instance locally via Ingress or
`http://<ha-ip>:3000`.

### HTTPS Only + HSTS

Set **HTTPS Only** to `true` if Invidious is behind a TLS-terminating reverse
proxy. This tells Invidious to generate `https://` links and redirect any plain
HTTP requests.

Set **Enable HSTS** to `true` alongside it to send a
`Strict-Transport-Security` header. Only do this once you are confident HTTPS
is working correctly — HSTS is hard to undo.

### External Port

If a reverse proxy listens on a port different from 3000 (for example, the
standard HTTPS port 443), set **External Port** to that port number. Invidious
uses this value when constructing absolute URLs in the API. Leave it at `0`
when not behind a proxy.

---

## Reverse proxy setup

A typical nginx snippet for proxying Invidious:

```nginx
server {
    listen 443 ssl;
    server_name invidious.example.com;

    # ... your SSL certificate config ...

    location / {
        proxy_pass http://<ha-ip>:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

With this in place, set:

| Option | Value |
|---|---|
| Domain | `invidious.example.com` |
| HTTPS Only | `true` |
| External Port | `0` (nginx forwards to 3000, which is the real port) |

---

## User accounts

| Option | Default | Notes |
|---|---|---|
| Allow Registration | `true` | Set to `false` on a private instance once you have created your account. |
| Allow Login | `true` | Set to `false` to make the instance fully read-only. |
| Enable Login Captcha | `true` | Built-in captcha, no third-party dependency. |
| Administrators | _(empty)_ | Enter your username to grant admin rights. Admins can change server-wide settings from the `/preferences` page. |

---

## Performance tuning

| Option | Default | Notes |
|---|---|---|
| Channel Threads | `1` | Increase to speed up subscription updates on large instances. |
| Feed Threads | `1` | Increase to speed up RSS feed refreshes. |
| Channel Refresh Interval | `30m` | How often subscribed channels are crawled for new videos. |
| HTTP Pool Size | `100` | Connections per YouTube domain. Raise if you see connection errors under load. |
| Enable User Notifications | `true` | Disable on large instances to reduce database writes. |

---

## Outbound proxy (HTTP Proxy)

If your Home Assistant host reaches the internet through an HTTP/HTTPS proxy,
fill in **HTTP Proxy Host** and **HTTP Proxy Port**. Add **HTTP Proxy Username**
and **HTTP Proxy Password** only if your proxy requires authentication.

> **Note:** This proxy is used for Invidious's requests to the YouTube API and
> for proxying video thumbnails and channel artwork. It does **not** route video
> streams — configure that in Invidious Companion instead.

---

## Invidious Companion

[Invidious Companion](https://github.com/iv-org/invidious-companion) is a
separate service that offloads video stream fetching from YouTube's servers.
It is optional but recommended for instances that serve multiple users.

To connect it, run Companion as a separate container (or add-on) and set:

| Option | Value |
|---|---|
| Companion Private URL | Internal URL Invidious uses to reach Companion, e.g. `http://companion:8282/companion` |
| Companion Public URL | *(Optional)* Public URL browsers use to fetch streams directly from Companion. Leave blank to proxy through Invidious. |
| Companion API Key | Shared 16-character secret — must match the key configured in Companion. |

---

## PubSubHub (instant new-video notifications)

Set **PubSubHub Subscriptions** to `true` (or a positive integer to cap
concurrent subscriptions) to receive instant notifications when subscribed
channels publish new videos. Requires:

- **Domain** to be set (PubSubHub callbacks use `/feed/webhook/v1`).
- **HMAC Key** to be set (used to verify webhook signatures).
- The instance to be reachable from the internet on the configured domain.

Without PubSubHub, Invidious polls for new videos every minute.

---

## Default user preferences

The options under the **Default user preferences** section set the starting
values for every new visitor (anyone without a preferences cookie). Logged-in
users can override all of these from their own `/preferences` page.

Notable ones to consider:

| Option | Notes |
|---|---|
| Default Language | Leave as `en-US` for public instances to avoid penalising users of other languages. |
| Default Region | Controls which region's trending and recommended content is shown. |
| Default Theme | `auto` follows the visitor's OS/browser dark-mode preference. |
| Default Video Quality | `dash` (adaptive) gives the best experience; `hd720` is a good static fallback. |
| Proxy Videos Through Instance | Keep `false` on shared instances — enabling it routes all video traffic through your server. |
| Default Home Page | Which feed to show on the home page. Must be one of: `Popular`, `Trending`, `Subscriptions`, `Playlists`. |

---

## Logs

Invidious logs go to the add-on's log output (visible under **Log** in the
add-on page). Adjust the **Log Level** option if you need more or less detail:

`Off` → `Fatal` → `Error` → `Warn` → **`Info`** (default) → `Debug` → `Trace` → `All`
