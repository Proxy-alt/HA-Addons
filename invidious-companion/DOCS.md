# Invidious Companion — Add-on Documentation

Invidious Companion is a lightweight side-car service that offloads video
stream fetching from YouTube's servers. Running it alongside the Invidious
add-on reduces rate-limiting and improves playback reliability, especially on
instances serving more than one user.

---

## Prerequisites

- The **Invidious** add-on must already be installed from this same repository.
- Companion is optional — Invidious works without it — but is recommended for
  any instance that serves more than one or two simultaneous viewers.

---

## How it works

Without Companion, every video stream request goes through the Invidious server
directly, meaning your Home Assistant host's IP talks to YouTube's CDN. Under
load this triggers rate-limiting.

With Companion, stream requests are delegated to a separate process that:

- applies its own proxy independently of Invidious's API proxy,
- fetches stream segments in parallel download threads, and
- presents a clean API boundary to Invidious so stream logic can evolve
  upstream without changing the add-on.

---

## Quick start

1. Install and start this add-on.
2. Open the **Invidious** add-on configuration and fill in the three Companion
   fields:

| Invidious option | Value |
|---|---|
| Companion Private URL | `http://localhost:8282/companion` |
| Companion Public URL | *(leave blank to proxy through Invidious)* |
| Companion API Key | The same 16-character key set here |

3. Restart the Invidious add-on.

> **Note:** `localhost` works because both add-ons share the same host network
> namespace on Home Assistant OS and Supervised installs. Use the actual HA host
> IP if you run a different install type.

---

## Configuration

### Companion API Key *(required)*

A 16-character shared secret. Pick any random string of exactly 16 characters.
This value must be identical in both this add-on and the **Companion API Key**
field of the Invidious add-on.

> **Tip:** Generate one with:
> ```
> openssl rand -hex 8
> ```

The add-on exits immediately at startup with a `[FATAL]` log message if this
field is blank.

### Download Threads

Controls how many parallel threads Companion uses to fetch video stream segments
from YouTube (default: `4`).

- Increase if you have multiple concurrent viewers and sufficient RAM/CPU.
- Decrease on constrained hardware (e.g. a Pi with limited memory) to reduce
  resource pressure.

---

## Outbound proxy

If your Home Assistant host reaches the internet through a proxy, configure it
here so Companion's stream requests are routed through it.

| Option | Description |
|---|---|
| **HTTP Proxy URL** | Full URL including port, e.g. `http://192.168.1.100:3128`. Sets both `HTTP_PROXY` and `http_proxy`. |
| **SOCKS Proxy Host** | Hostname or IP of a SOCKS4/5 proxy. Leave blank to disable. |
| **SOCKS Proxy Port** | Port for the SOCKS proxy (default: `1080`). Only used when SOCKS Proxy Host is set. |

> **Note:** These settings only affect Companion's stream requests. Invidious's
> own requests to the YouTube API use the proxy configured in the Invidious
> add-on, not this one.

---

## Port

Companion listens on port **8282**. The host port mapping is enabled by default
so Invidious can reach it via `http://<ha-ip>:8282`.

You can disable the host port mapping under **Network** if you only need
Companion to be reachable from within the same host via `localhost:8282` (the
typical setup on HAOS / Supervised).

---

## Networking between add-ons

Both add-ons run in the host network namespace on Home Assistant OS and
Supervised installs, so they communicate directly over `localhost`.

```
Browser / client
      │
      ▼
 [Invidious :3000]  ──API calls──▶  YouTube API
      │
      │  stream redirect / proxy
      ▼
 [Companion :8282]  ──stream fetching──▶  YouTube CDN
```

If Companion is configured with a **Companion Public URL**, browsers fetch
streams directly from Companion (bypassing Invidious entirely for video data).
If **Companion Public URL** is left blank, Invidious proxies the streams on
Companion's behalf — simpler to set up but routes all video traffic through
your HA server.

---

## Troubleshooting

### Companion Key mismatch

**Symptom:** Videos fail to load; Invidious logs show an authentication error
from Companion.

**Fix:** Make sure the key in this add-on's **Companion API Key** field is
exactly the same string as the **Companion API Key** field in the Invidious
add-on. Both are 16 characters. Restart both add-ons after changing either key.

---

### Add-on exits immediately on start

**Symptom:** The add-on starts and stops in seconds; the log shows `[FATAL]
Companion Key is not set`.

**Fix:** Open this add-on's configuration, enter a 16-character key in the
**Companion API Key** field, and save.

---

### Invidious cannot reach Companion

**Symptom:** Invidious logs show a connection refused or timeout when contacting
`http://localhost:8282`.

**Things to check:**

1. This add-on is running (green dot in the HA add-on list).
2. The **Companion Private URL** in the Invidious add-on is set to
   `http://localhost:8282/companion` (note the `/companion` path).
3. Port 8282 is not in use by another process. If it is, disable the host port
   mapping under **Network** here and use a different internal approach, or
   change the mapped host port.

---

### Streams are slow or buffer frequently

- Increase **Download Threads** (try `8` or `16` if your hardware allows).
- Check your network path to YouTube — if you are on a slow link, Companion
  cannot overcome the underlying bandwidth constraint.
- If you use a proxy, confirm the proxy is performing well. Try removing the
  proxy temporarily to isolate it.

---

## Logs

Companion logs appear in the add-on's **Log** tab. Check here first if streams
are failing, if you suspect a key mismatch with the Invidious add-on, or if you
want to confirm Companion started cleanly.

On a successful start the log will show:

```
[INFO] Starting Invidious Companion on port 8282...
```
