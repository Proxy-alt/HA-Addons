# Hostapd — Add-on Documentation

[hostapd](https://w1.fi/hostapd/) turns a Wi-Fi network interface into one
or more wireless access points (APs). This add-on installs the official
Debian package and generates `hostapd.conf` from the options you set in the
Home Assistant UI. Pair it with a DHCP/DNS add-on — e.g. the official
[Dnsmasq](https://github.com/home-assistant/addons/tree/master/dnsmasq)
add-on from the Home Assistant Add-ons repository — to hand out leases and
DNS to devices that join an AP.

---

## Why this add-on needs the permissions it asks for

Home Assistant add-ons are sandboxed by default. hostapd needs several of
those restrictions lifted to actually drive a radio:

| Setting | Value | Why |
|---|---|---|
| `host_network` | `true` | A wireless interface (e.g. `wlan0`) is tied to its physical radio (`phy0`) and cannot be moved into an isolated container network namespace the way a virtual `veth` pair can. hostapd must see and bind the interface as it exists on the host. |
| `privileged` | `NET_ADMIN`, `NET_RAW` | `NET_ADMIN` lets hostapd bring the interface up and configure it via `nl80211`/netlink. `NET_RAW` is required by hostapd's driver backend to send and receive raw 802.11 management frames. |
| `devices` | `/dev/rfkill` | Lets the add-on run `rfkill unblock wifi` on start, in case the radio is soft-blocked. |
| `apparmor` | `true` (custom profile) | The Supervisor's default AppArmor profile blocks the netlink and raw-packet socket operations above. This add-on ships its own `apparmor.txt` that confines those operations to the `hostapd` binary specifically, rather than disabling AppArmor for the whole add-on. |

None of this grants access to unrelated hardware — `full_access` and other
broad device grants are deliberately **not** used.

---

## Before you start: free the interface

On most systems, Wi-Fi interfaces are managed by `wpa_supplicant` or
NetworkManager. If either is actively managing the interface you point
hostapd at, they will fight over control and hostapd will fail to start
(commonly seen as `nl80211: Could not configure driver mode` or similar).

- If you're using a dedicated USB Wi-Fi adapter for the AP, this is usually
  not an issue as long as it isn't also configured as a client network in
  Home Assistant OS's network settings.
- If you're using the same adapter that Home Assistant OS also uses for
  Wi-Fi client connectivity, you cannot run both at once on that adapter —
  use a second adapter for the AP.

---

## Configuration

### Radio (Wi-Fi Interface / Band / Channel / Country Code)

`interface` is the host interface to convert into an AP, e.g. `wlan0`. Check
AP-mode support on the host with `iw list` (look for `AP` under "Supported
interface modes").

`hw_mode` selects 2.4 GHz (`b`/`g`) or 5 GHz (`a`). `channel` must be valid
for both the selected band and `country_code` — set `channel` to `0` to let
hostapd pick a channel automatically (ACS), or set it explicitly. `country_code`
also determines the legal transmit power and channel set for your region —
set it to your actual country, not a default.

### 802.11 mode toggles

`ieee80211n` (Wi-Fi 4), `ieee80211ac` (Wi-Fi 5, 5 GHz only), and `ieee80211ax`
(Wi-Fi 6) enable progressively newer PHY modes if your adapter supports them.
`ieee80211h` enables DFS/TPC, required on some 5 GHz channels that share
spectrum with radar. `ieee80211d` advertises the configured country code to
clients — leave it enabled. `ht_capab`/`vht_capab` are raw hostapd capability
strings for advanced tuning; leave empty to use the driver's defaults.

### Radio tuning

`wmm_enabled` (QoS extensions, required for 802.11n/ac/ax), `beacon_int`,
`dtim_period`, `max_num_sta` (0 = unlimited, shared across every AP below),
`rts_threshold`, and `fragm_threshold` (-1 disables both) are exposed for
advanced tuning. Defaults are sane for nearly all setups.

### Access Points (`access_points`)

Each entry is one SSID. All entries broadcast simultaneously from the same
radio using hostapd's multi-BSS support (`wlan0`, `wlan0_1`, `wlan0_2`, ...) —
how many your adapter can actually drive at once depends on its chipset;
consumer 802.11n/ac chips typically support at least 4.

Each access point has:

- **ssid** — the broadcast network name.
- **hide_ssid** — don't broadcast the name; devices must know it in advance.
  Does not meaningfully improve security.
- **security_mode** — one of:
  - `open` — no encryption. Not recommended outside of testing.
  - `owe` — WPA3 Enhanced Open. Encrypts traffic per-client without a shared
    password (opportunistic wireless encryption) — a strict security upgrade
    over `open` with the same "no password" UX. Requires client support.
  - `wpa2_personal` — WPA2-PSK. The common default; needs `wpa_passphrase`.
  - `wpa3_personal` — WPA3-SAE. Stronger than WPA2-PSK, resistant to offline
    dictionary attacks; needs `wpa_passphrase`. Some older clients don't
    support SAE — use `wpa2_wpa3_personal` if you need to support both.
  - `wpa2_wpa3_personal` — Transition mode: accepts both WPA2-PSK and
    WPA3-SAE clients on the same SSID with one `wpa_passphrase`.
  - `wpa2_enterprise` — WPA2-Enterprise (802.1X). Authenticates each client
    individually against the RADIUS server configured below instead of a
    shared passphrase. `wpa_passphrase` is ignored.
  - `wpa3_enterprise` — WPA3-Enterprise. Same as `wpa2_enterprise` but
    mandates Protected Management Frames (PMF), matching the WPA3 spec.
- **wpa_passphrase** — WPA2/WPA3-Personal passphrase (8-63 characters).
  Ignored for `open`, `owe`, and the Enterprise modes.

Protected Management Frames (`ieee80211w`) are derived automatically from
`security_mode` — required for `owe`/`wpa3_personal`/`wpa3_enterprise`,
optional for the other secured modes, off for `open` — this isn't a
separate option because getting it wrong silently breaks the mode's spec
guarantee.

#### About Enterprise modes and EAP method (PEAP vs. EAP-TLS)

hostapd itself doesn't implement EAP methods — for `wpa2_enterprise` and
`wpa3_enterprise` it just relays 802.1X frames to the RADIUS server
configured below, and the RADIUS server negotiates the actual EAP method
(PEAP/MSCHAPv2, EAP-TLS, TTLS, ...) with the client. Both modes here produce
the same hostapd-side configuration; whether clients authenticate with a
password (PEAP) or a client certificate (EAP-TLS) is controlled entirely by
the RADIUS server's own configuration — see this repository's
[FreeRADIUS add-on](../freeradius/) for that half of the setup.

### RADIUS Server (`radius`)

Only needed if at least one access point above uses `wpa2_enterprise` or
`wpa3_enterprise`. Points hostapd at an external RADIUS server — e.g. this
repository's [FreeRADIUS](../freeradius/) add-on, or any other RFC
2865/2866-compliant server.

- **enabled** — must be `true` for any Enterprise access point to start.
- **nas_identifier** — the NAS-Identifier this hostapd instance presents to
  the RADIUS server. Must match what's allowed in the RADIUS server's client
  list.
- **own_ip_addr** — the IP address hostapd uses as its source address when
  talking to the RADIUS server. Required — hostapd cannot reliably
  auto-detect this from inside a container.
- **auth_server_addr** / **auth_server_port** / **auth_server_secret** —
  RADIUS authentication endpoint and shared secret. All three are required.
- **acct_enabled** / **acct_server_addr** / **acct_server_port** /
  **acct_server_secret** — optional RADIUS accounting (start/stop/interim
  records). If enabled, address and secret are both required.

---

## Troubleshooting

### Add-on exits immediately with an nl80211 error

The interface is likely still owned by NetworkManager/wpa_supplicant, or
doesn't support AP mode. See "Before you start" above.

### "wpa_passphrase must be 8-63 characters"

WPA2/WPA3-Personal requires a passphrase of 8 to 63 characters. The add-on
validates this before starting and refuses to run with an out-of-range
value rather than letting hostapd fail less clearly.

### "radius.* is/are required when an Enterprise access point is configured"

An access point is set to `wpa2_enterprise`/`wpa3_enterprise` but the
`radius` section is incomplete. Set `radius.enabled: true` and fill in
`auth_server_addr`, `auth_server_secret`, and `own_ip_addr` at minimum.

### Enterprise clients fail to authenticate

Check the RADIUS server's logs, not hostapd's — hostapd only relays 802.1X
frames; the RADIUS server enforces the actual EAP method and user/certificate
policy. If you're using the FreeRADIUS add-on, its NAS client entry's
`ipaddr`/`secret` must match this add-on's `radius.own_ip_addr` and
`auth_server_secret` exactly.

### Clients can associate but get no IP address

hostapd only handles the radio/association layer — it does not run a DHCP
server. Install and configure a DHCP/DNS add-on (e.g. the official Dnsmasq
add-on) pointed at the same interface to hand out leases.
