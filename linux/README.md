# Hermes Dashboard — LAN Exposure Package

A self-contained deployable package that exposes the **Hermes Agent dashboard**
(bound to `127.0.0.1:9119`) to other devices on the local network **without**
using `--insecure` or modifying the dashboard's bind address.

> **Purpose**: Let another Hermes agent (or human) reproduce the exact setup
> that was built on the source machine. All config files use **template
> variables** so they work on any Fedora/RHEL-like system.

---

## Architecture

```
LAN client → 192.168.1.x:LAN_PORT
  → firewalld (port LAN_PORT/tcp open)
  → iptables DNAT (LAN_PORT → INTERNAL_PORT, requires route_localnet=1)
  → nginx (0.0.0.0:INTERNAL_PORT, rewrites Host → 127.0.0.1)
  → Hermes dashboard (127.0.0.1:DASHBOARD_PORT)
```

**Why nginx?** Hermes validates the HTTP `Host` header against its bound
interface (`127.0.0.1`). Without rewriting it, requests from LAN browsers
are rejected with `"Invalid Host header"`. Nginx strips the LAN IP from the
Host header and substitutes `127.0.0.1`.

---

## What's In This Package

```
hermes-dashboard-lan-package/
├── README.md                                  ← this file
├── deploy.sh                                  ← one-shot deploy (run as root)
├── deploy-dashboard-user-service.sh           ← dashboard auto-start (run as user)
├── verify.sh                                  ← post-deploy verification
├── rollback.sh                                ← remove everything cleanly
├── config/
│   ├── nginx-hermes-dashboard.conf            ← nginx reverse proxy (template)
│   ├── sysctl-hermes-route-localnet.conf      ← route_localnet=1
│   ├── hermes-dashboard-proxy.service         ← systemd system service (iptables DNAT)
│   └── hermes-dashboard.service               ← systemd user service (dashboard auto-start)
└── patches/
    └── allow-lan-origins.patch                ← git patch for web_server.py
```

---

## What The Agent Created (for reference)

### System config files written

| File | Purpose |
|---|---|
| `/etc/nginx/conf.d/hermes-dashboard.conf` | Nginx reverse proxy: `0.0.0.0:9191 → 127.0.0.1:9119` |
| `/etc/sysctl.d/99-hermes-route-localnet.conf` | `net.ipv4.conf.all.route_localnet=1` |
| `/etc/systemd/system/hermes-dashboard-proxy.service` | Oneshot service: iptables DNAT rules + sysctl, persists across reboots |
| `~/.config/systemd/user/hermes-dashboard.service` | User service: auto-starts `hermes dashboard --no-open` at boot |

### iptables rules added

```bash
# External traffic: DNAT LAN:9119 → 127.0.0.1:9191
iptables -t nat -A PREROUTING -p tcp --dport 9119 -j DNAT --to-destination 127.0.0.1:9191

# Local traffic to own external IP: same DNAT (skip loopback)
iptables -t nat -A OUTPUT -p tcp --dport 9119 ! -d 127.0.0.0/8 -j DNAT --to-destination 127.0.0.1:9191
```

### SELinux changes

```bash
semanage port -a -t http_port_t -p tcp 9191
setsebool -P httpd_can_network_connect 1
```

### Firewall

```bash
firewall-cmd --add-port=9119/tcp --permanent
```

### Hermes web_server.py patches

Two surgical changes in `hermes_cli/web_server.py`:

1. **CORS regex** (line ~238): Added RFC1918 private IP ranges so the CORS
   middleware accepts `Origin` headers from LAN addresses.

2. **`_is_accepted_host`** (line ~389): When the dashboard is bound to loopback,
   also accept private LAN IPs as valid `Host`/`Origin` values (since the
   request arrives through nginx on the same machine).

These are the *only* Hermes source changes needed. Everything else is pure
system administration.

### systemd boot order

```
Fedora boot
├─ systemd (user)  ─── hermes-gateway.service
│                    └─ Gateway messaging platforms
├─ systemd (user)  ─── hermes-dashboard.service       ← user service
│                    └─ hermes dashboard --no-open
│                    └─ Port 127.0.0.1:9119
├─ systemd (system) ─ nginx.service
│                    └─ Proxy 0.0.0.0:9191 → 127.0.0.1:9119
└─ systemd (system) ─ hermes-dashboard-proxy.service
                     └─ iptables DNAT 9119 → 9191
                     └─ sysctl route_localnet=1
```

---

## Quick Start (for Another Agent)

### Prerequisites

- Fedora / RHEL / CentOS (or any `dnf`-based distro)
- Hermes Agent installed with dashboard at `~/.hermes`
- `sudo` access
- Static LAN IP recommended (so browser bookmarks survive DHCP changes)

### Step 1 — Deploy the infrastructure

```bash
# As root — installs nginx, firewall, iptables, SELinux, sysctl
sudo ./deploy.sh

# Custom ports (if Hermes dashboard listens on a different port):
sudo ./deploy.sh --port 9119 --internal-port 9191
```

This handles everything *except* the web_server.py patch and the dashboard
auto-start service.

### Step 2 — Patch Hermes web_server.py

The deploy script will prompt you. Or do it manually:

```bash
cd ~/.hermes/hermes-agent
git apply /path/to/patches/allow-lan-origins.patch
```

If the patch fails (already applied), confirm with:
```bash
grep '192\.168' hermes_cli/web_server.py
```

### Step 3 — Restart the dashboard

```bash
hermes dashboard --stop
hermes dashboard --no-open &

# Or if using the user service:
systemctl --user restart hermes-dashboard.service
```

### Step 4 — (Optional) Dashboard auto-start at boot

```bash
./deploy-dashboard-user-service.sh
```

This installs a systemd **user** service so the dashboard starts
automatically when the machine boots, without requiring a desktop login.

### Step 5 — Verify

```bash
./verify.sh
```

Also test from a LAN device:
```bash
curl -s http://192.168.1.YOUR_IP:9119/api/status
```

Should return JSON with version info — not an error.

---

## Port Configuration Reference

| Variable | Default | Description |
|---|---|---|
| `LAN_PORT` | `9119` | Port exposed to LAN clients (used by iptables + firewall) |
| `INTERNAL_PORT` | `9191` | Port nginx listens on internally (never reaches Hermes directly) |
| `DASHBOARD_PORT` | same as `LAN_PORT` | Port Hermes dashboard binds to on `127.0.0.1` |

### Port mapping explained

```
Client → LAN_PORT (9119) → iptables DNAT → INTERNAL_PORT (9191) → nginx → 127.0.0.1:DASHBOARD_PORT (9119)
```

---

## Rollback

```bash
sudo ./rollback.sh [--port LAN_PORT]
```

To also revert the Hermes source patches:
```bash
cd ~/.hermes/hermes-agent
git checkout -- hermes_cli/web_server.py
systemctl --user restart hermes-dashboard.service
```

---

## Pitfalls (for the Agent to Watch Out For)

| Pitfall | Symptom | Solution |
|---|---|---|
| **SELinux blocks nginx** | 502 Bad Gateway from LAN | `semanage port -a -t http_port_t -p tcp 9191` + `setsebool httpd_can_network_connect 1` |
| **route_localnet=0** | iptables DNAT drops packets silently | `sysctl -w net.ipv4.conf.all.route_localnet=1` (persist in `/etc/sysctl.d/`) |
| **iptables OUTPUT without `! -d 127.0.0.0/8`** | Local processes to 127.0.0.1:9119 get caught by DNAT → loop | Add `! -d 127.0.0.0/8` to the OUTPUT rule |
| **SSE buffering** | Dashboard events feed doesn't update in real-time | Add `proxy_buffering off; proxy_cache off;` to nginx config |
| **Double Origin check** | CORS passes but `_is_accepted_host` rejects | Both CORS regex AND `_is_accepted_host` must be patched |
| **Dashboard doesn't restart after patch** | Old code still running | Kill old `hermes dashboard` process — `systemctl --user restart hermes-dashboard.service` |
| **Nginx can't bind 0.0.0.0:DASHBOARD_PORT** | Port already in use | Use a different INTERNAL_PORT (9191) + DNAT |
| **Dashboard auto-starts browser** | Browser opens on every boot | Always use `--no-open` flag in headless/server environments |

---

## Hermes Skill

The workflow is also saved as a skill under `hermes-dashboard-lan-expose`
in the source agent's skills directory. Load it with:

```python
skill_view(name='hermes-dashboard-lan-expose')
```

The skill's SKILL.md contains the full procedure with exact commands and
rollback steps.
