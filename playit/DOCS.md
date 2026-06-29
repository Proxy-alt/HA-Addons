# Playit.gg — Add-on Documentation

[Playit.gg](https://playit.gg) is a global proxy service that lets you expose
local services (game servers, HTTP services, etc.) to the internet without
configuring port forwarding on your router. The agent makes an outbound
connection to playit.gg's network; all tunnel routing configuration is done
through the [playit.gg dashboard](https://app.playit.gg).

---

## First-time setup

1. **Start the add-on with Secret Key left blank.**
   The agent will print a claim URL in the **Log** tab (look for a line
   starting with `https://playit.gg/mc/`).

2. **Visit the claim URL** in your browser. If you are not logged in you will
   be prompted to create or sign in to a playit.gg account.

3. **Confirm the agent registration.** The dashboard will show the new agent.

4. **Copy the secret key** — on the agent page, reveal and copy the secret
   value shown under *Agent Secret*.

5. **Paste the secret key** into the **Secret Key** field in the add-on
   configuration, save, and restart the add-on.

From this point on the agent will authenticate automatically on start.

---

## Creating tunnels

All tunnel management (adding, removing, changing ports or protocols) is done
in the [playit.gg dashboard](https://app.playit.gg) — no local configuration
is required. The agent connects to playit.gg's network on startup and forwards
traffic to whatever local services you configure through the dashboard.

---

## Configuration

### Secret Key *(optional on first run)*

The agent secret obtained from the playit.gg dashboard after claiming the
agent. Leave blank on first run and follow the first-time setup steps above.

Once set, the key is passed to the agent via the `PLAYIT_SECRET` environment
variable. The value is stored in the add-on configuration and persists across
restarts.

---

## Data persistence

The agent stores its state (including tunnel assignments) in the add-on's
persistent data volume. This means tunnel configuration survives add-on
updates and Home Assistant reboots without needing to re-claim the agent.

---

## Troubleshooting

### No claim URL appears in the logs

The claim URL is printed by the playit agent to stdout. If you do not see it:

- Make sure the **Secret Key** field is blank (a previously set key prevents
  the claim flow from running).
- Restart the add-on and open the **Log** tab immediately.
- The URL appears near the start of the log output.

### Agent connects but tunnels do not forward traffic

- Confirm the tunnel target port in the playit.gg dashboard matches the port
  your local service is listening on.
- Some services bind to `127.0.0.1` only — if the service needs to accept
  connections from the playit agent running in the same container, binding to
  `0.0.0.0` may be required.

### Add-on exits immediately

Check the **Log** tab for a fatal error. The most common cause is a malformed
or expired secret key. Clear the **Secret Key** field and re-run the
first-time setup to obtain a fresh key.
