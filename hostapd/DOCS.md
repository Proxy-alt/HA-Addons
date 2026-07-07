# Hostapd — Add-on Documentation

[hostapd](https://w1.fi/hostapd/) turns a Wi-Fi network interface into a
wireless access point (AP). This add-on installs the official Debian package
and generates `hostapd.conf` from the options you set in the Home Assistant
UI. Pair it with a DHCP/DNS add-on — e.g. the official
[Dnsmasq](https://github.com/home-assistant/addons/tree/master/dnsmasq)
add-on from the Home Assistant Add-ons repository — to hand out leases and
DNS to devices that join the AP.

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

### Wi-Fi Interface

The host interface to convert into an AP, e.g. `wlan0`. Check AP-mode support
on the host with `iw list` (look for `AP` under "Supported interface modes").

### Network Name (SSID) / Wi-Fi Password

The broadcast network name and WPA2 passphrase. Leave the passphrase empty to
run an **open, unencrypted network** — the add-on logs a warning when you do
this, and it is not recommended outside of testing.

### Band / Channel / Country Code

`hw_mode` selects 2.4 GHz (`b`/`g`) or 5 GHz (`a`). The channel must be valid
for both the selected band and the configured `country_code`, which also
determines the legal transmit power and channel set for your region — set it
to your actual country, not a default.

### Enable 802.11n / Hide SSID

Optional throughput and visibility toggles. Hiding the SSID does not provide
meaningful security — it only stops the name showing in a casual scan.

---

## Troubleshooting

### Add-on exits immediately with an nl80211 error

The interface is likely still owned by NetworkManager/wpa_supplicant, or
doesn't support AP mode. See "Before you start" above.

### "wpa_passphrase must be 8-63 characters"

WPA2 requires a passphrase of 8 to 63 characters. The add-on validates this
before starting and refuses to run with an out-of-range value rather than
letting hostapd fail less clearly.

### Clients can associate but get no IP address

hostapd only handles the radio/association layer — it does not run a DHCP
server. Install and configure a DHCP/DNS add-on (e.g. the official Dnsmasq
add-on) pointed at the same interface to hand out leases.
