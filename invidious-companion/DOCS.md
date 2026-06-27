# Invidious Companion — Add-on Documentation

Invidious Companion is a lightweight side-car service that offloads video
stream fetching from YouTube's servers. Running it alongside the Invidious
add-on reduces rate-limiting and improves playback reliability, especially on
instances serving more than one user.

---

## How it works

Without Companion, every video request goes through the Invidious server —
which means your Home Assistant host's IP talks directly to YouTube CDN.
With Companion, stream requests are delegated to a separate process that can
apply its own proxy, manage connections independently, and buffer streams in
parallel download threads.

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

> **Note:** "localhost" works because both add-ons share the same host network
> namespace on Home Assistant OS / Supervised installs. Use the actual host IP
> if that does not apply to your setup.

---

## Configuration

### Companion API Key *(required)*

A 16-character shared secret. Choose any random string of exactly 16
characters — for example `aBcDeFgHiJkLmNoP`. This value must be identical in
both this add-on and the **Companion API Key** field of the Invidious add-on.

> **Tip:** You can generate one with:
> ```
> openssl rand -hex 8
> ```

### Download Threads

Controls how many video streams Companion fetches in parallel (default: `4`).
Increase this if you have many concurrent viewers; lower it to reduce CPU and
memory usage on constrained hardware.

---

## Outbound proxy

If your Home Assistant host reaches the internet through a proxy, configure
it here so Companion's YouTube requests are routed through it.

- **HTTP Proxy URL** — full URL including port, e.g.
  `http://192.168.1.100:3128`. Companion will set both `HTTP_PROXY` and
  `http_proxy` environment variables.
- **SOCKS Proxy Host / Port** — hostname and port of a SOCKS4/5 proxy.

> **Note:** Proxy settings here only affect Companion's stream requests.
> Invidious's own API requests to YouTube use the proxy configured in the
> Invidious add-on.

---

## Port

Companion listens on port **8282**. This port is mapped to the host so
Invidious can reach it at `http://<ha-ip>:8282`.

You can disable the host port mapping under **Network** if you only need
Companion to be reachable from within the same host (via `localhost:8282`).

---

## Logs

Companion logs appear in the add-on's **Log** tab. Check here first if
streams are failing or if you suspect a key mismatch with the Invidious
add-on.
