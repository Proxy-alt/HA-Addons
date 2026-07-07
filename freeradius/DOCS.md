# FreeRADIUS — Add-on Documentation

[FreeRADIUS](https://freeradius.org/) is a RADIUS (RFC 2865/2866) server.
This add-on installs the official Debian package and generates its client
list, local user database, and EAP settings from the options you set in the
Home Assistant UI. It's designed to pair with this repository's
[Hostapd](../hostapd/) add-on's `wpa2_enterprise`/`wpa3_enterprise` access
points, but works with any RADIUS-authenticating NAS.

---

## How the pieces fit together

1. In **this** add-on, add an entry to `clients` describing the NAS
   (e.g. the Hostapd add-on) that will send requests here.
2. In the **Hostapd** add-on, set `radius.own_ip_addr` to the IP the NAS
   uses to reach this server, and `radius.auth_server_secret` to the same
   value as the matching `clients[].secret` here.
3. Add at least one entry to `users` if you want PEAP/TTLS (password)
   logins to work. EAP-TLS clients authenticate with a certificate instead
   and don't need a `users` entry.

---

## Configuration

### RADIUS Clients (`clients`)

One entry per NAS allowed to talk to this server:

- **name** — a label for the client (shown in FreeRADIUS logs).
- **ipaddr** — the NAS's source IP address. Must match exactly what the NAS
  presents (for the Hostapd add-on, this is `radius.own_ip_addr`).
- **secret** — shared secret used to authenticate and encrypt RADIUS
  traffic between the NAS and this server. Must match the NAS's configured
  secret exactly.

At least one client is required — the add-on refuses to start without one.

### Local Users (`users`)

Username/password pairs, stored as `Cleartext-Password` entries. Used when
a client authenticates with a password-based EAP method (PEAP or TTLS,
which tunnel MSCHAPv2 over TLS). Not required for EAP-TLS-only deployments.

### EAP Settings (`eap`)

- **default_eap_type** — `peap`, `ttls`, or `tls` (EAP-TLS). This is the EAP
  method FreeRADIUS offers first; most clients negotiate down to whichever
  method they support, but setting this to match your intended method
  avoids ambiguity.
- **tls_verify_client_cert** — require clients to present a certificate
  signed by this server's CA. Leave `false` for PEAP/TTLS (password auth).
  **Set to `true` for EAP-TLS** — without it, EAP-TLS does not actually
  verify who's connecting.

### Certificates

On first run, the add-on generates a self-signed CA and server certificate
and persists them to `/data/certs` (survives restarts/updates — regenerating
them would invalidate any client that has pinned the old CA). For EAP-TLS,
clients need a certificate signed by this CA; issuing client certificates
is outside the scope of this add-on — use the generated `ca.pem`/`ca.key`
in `/data/certs` with `openssl` to sign client certificates yourself.

---

## Troubleshooting

### "No RADIUS clients configured" / add-on refuses to start

Add at least one entry to `clients` with `name`, `ipaddr`, and `secret` all
set.

### Hostapd's Enterprise access point can't reach this server

Double-check that Hostapd's `radius.own_ip_addr` matches this add-on's
`clients[].ipaddr` exactly, and that `radius.auth_server_secret` (Hostapd
side) matches `clients[].secret` (this add-on) exactly — RADIUS silently
drops requests with a mismatched shared secret rather than returning a
clear error.

### PEAP/TTLS clients fail to authenticate

Check that a matching entry exists in `users`. Password-based EAP methods
need the plaintext password on this side to validate the tunneled
MSCHAPv2 exchange.

### EAP-TLS clients fail to authenticate

The client needs a certificate signed by this add-on's CA
(`/data/certs/ca.pem`). Also confirm `tls_verify_client_cert` is `true` —
required for EAP-TLS to actually check the client's identity.
