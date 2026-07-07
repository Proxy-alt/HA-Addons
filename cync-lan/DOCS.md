# Cync LAN — Add-on Documentation

[cync-lan](https://github.com/baudneo/cync-lan) masquerades as the Cync/C by
GE cloud server so Wi-Fi bulbs, plugs, and switches keep working — and stay
controllable — after your internet connection or the Cync cloud goes down.
It bridges devices into Home Assistant over MQTT using the same JSON schema
the official Mosquitto/MQTT integration expects, so devices are auto-added
via MQTT discovery.

This only works for Cync's **Wi-Fi** devices. Bluetooth-only devices are
unaffected and keep working through the Cync app as normal.

---

## How it works, in short

1. Cync Wi-Fi devices normally phone home to `cm.gelighting.com` (or
   `cm-ge.xlink.cn` on older firmware) over TLS.
2. You export your device list once from the Cync cloud using this add-on's
   built-in web exporter.
3. You override those domains in your router/DNS server to point at this
   Home Assistant host instead.
4. Devices reconnect to the add-on instead of the cloud; it bridges their
   state to Home Assistant over MQTT.

None of this touches Bluetooth. The Cync **phone app** should be left
pointed at the real cloud (see "Don't redirect your phone" below).

---

## Before you start

### 1. Export your device list

1. Set **Cync Account Email** / **Cync Account Password** to your Cync app
   login and make sure **Export Device List** is enabled.
2. Start the add-on.
3. Visit `http://<home-assistant-ip>:23778` and use the export button to
   pull your device list from the Cync cloud. This writes `cync_mesh.yaml`
   into this add-on's persistent config directory.
4. You can disable **Export Device List** afterwards if you don't want the
   export UI reachable; re-enable it later if you add more devices.

### 2. Redirect device DNS

Cync devices need the cloud domain(s) they use redirected to this add-on's
IP (the Home Assistant host's LAN IP, since this add-on uses host
networking):

| Firmware | Domain |
|---|---|
| Newer | `cm.gelighting.com`, `cm-sec.gelighting.com` |
| Older | `cm-ge.xlink.cn` |

Check which one your devices use by watching DNS query logs for `xlink.cn`
or `gelighting.com`. How to set the override depends on your router/DNS
server (Pi-hole, AdGuard Home, OPNsense/Unbound, etc.) — see upstream's
[DNS redirection guide](https://github.com/baudneo/cync-lan/blob/python/docs/DNS.md)
for setup steps per platform.

**Don't redirect your phone.** The Cync app should keep talking to the real
cloud — it needs that to add new devices, and local control doesn't go
through it anyway. Selective (per-device) DNS overrides, where your router
supports them, avoid this problem entirely.

**Power cycle your devices** after changing DNS so they re-resolve the
domain and reconnect to this add-on instead of the cloud.

**Adding new devices requires temporarily removing the DNS override** (or
excluding your phone if using selective/per-device overrides) — the Cync
app can't finish pairing a new device while its own traffic is redirected.

---

## Configuration

### Cync Account Email / Password

Your Cync app login. Only used by the export web UI (port 23778) to pull
your device list from the cloud — not needed for the LAN bridge itself once
you've exported.

### Export Device List

Toggles the export web UI on port 23778. Requires the account credentials
above when enabled.

### Secret Key

Encrypts the cached Cync cloud auth token at rest. Leave empty — the add-on
generates one on first start and saves it back to this option.

### MQTT Broker Host / Port / Username / Password

Connection details for the MQTT broker devices are bridged through. Defaults
target the official Mosquitto add-on's internal address
(`core-mosquitto:1883`); change these if you use a different broker.

### MQTT Topic Prefix

Topic prefix used for state and command messages. Leave at `cync_lan` unless
it collides with something else on your broker.

### Max Device Connections

Caps how many Cync Wi-Fi devices can hold a connection to the LAN server at
once. Raise this if you have more always-on devices than the default allows.

### Device IP Whitelist

Optional list of IPs allowed to connect. Leave empty to accept any device
that resolves this add-on's address — tightening this only matters if
you're doing a network-wide DNS override and want to limit which client IPs
can pretend to be a Cync device.

### Cync Cloud IP

The real Cync cloud server IP, used internally to keep the phone app's
cloud traffic working. Only change this if upstream's default no longer
resolves.

---

## Troubleshooting

### Devices don't reconnect after the DNS change

Power cycle them — they only re-resolve the cloud domain on boot/reconnect,
not while an existing connection is still open.

### Export UI can't reach the cloud

Double check **Cync Account Email**/**Password** are set and that
**Export Device List** is enabled, then check the add-on log for the
specific cloud API error.

### Can't add a new device in the Cync app

A network-wide DNS override blocks the app from finishing setup of new
devices. Temporarily remove the override (or exclude your phone if your
router supports per-device overrides), add the device, then restore it.

### Devices connect but don't show up in Home Assistant

Confirm the MQTT broker settings match a broker Home Assistant's MQTT
integration is also connected to, and check this add-on's log for MQTT
connection errors.
