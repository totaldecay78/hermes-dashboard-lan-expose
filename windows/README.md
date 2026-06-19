# Hermes Dashboard — LAN Exposure (Windows / PowerShell 5.1)

A self-contained deployable package that exposes the **Hermes Agent dashboard**
(bound to `127.0.0.1:9119`) to other devices on the local network **without**
using `--insecure` or modifying the dashboard's bind address.

> **Windows edition** — uses built-in Windows tools only (no nginx, no cygwin,
> no WSL). The same Hermes `web_server.py` patch (Python source = cross-platform)
> handles CORS + Host validation. Port forwarding uses `netsh interface portproxy`,
> firewall uses `netsh advfirewall`, and auto-start uses a Scheduled Task.

---

## Architecture

```
LAN client → 192.168.1.x:LAN_PORT
  → Windows Firewall (port LAN_PORT/tcp open)
  → netsh interface portproxy (0.0.0.0:LAN_PORT → 127.0.0.1:LAN_PORT)
  → Hermes dashboard (127.0.0.1:LAN_PORT)
```

**Why no nginx?** Unlike the Linux version, on Windows the standard approach
uses `netsh interface portproxy` which tunnels TCP directly. The Hermes
`web_server.py` patch (already included) teaches the dashboard to accept
RFC1918 private LAN IPs as valid `Host` headers — so the LAN browser's
`Host: 192.168.1.100:9119` is accepted without needing a reverse proxy to
rewrite it.

**When you might still want nginx on Windows:**
- You want an extra security layer
- You need WebSocket/SSE header manipulation
- nginx for Windows (`nginx.org/en/download.html`) works with the same config

---

## What's In This Package

```
hermes-dashboard-lan-expose-windows/
├── README.md                                  ← this file
├── deploy.ps1                                 ← one-shot deploy (Admin)
├── verify.ps1                                 ← post-deploy verification
├── rollback.ps1                               ← remove everything cleanly
├── deploy-dashboard-startup.ps1               ← Scheduled Task auto-start
└── patches/
    └── allow-lan-origins.patch                ← Hermes web_server.py patch
```

---

## Quick Start

### Prerequisites

- **Windows 8.1 / 10 / 11** or **Windows Server 2012 R2+**
- **PowerShell 5.1** (ships with Windows — no install needed)
- **Hermes Agent** installed with the dashboard
- **Run as Administrator** (required for portproxy + firewall)

### Step 1 — Deploy the infrastructure

```powershell
# Open PowerShell as Administrator, then:
.\deploy.ps1

# Custom port (if Hermes dashboard is on a different port):
.\deploy.ps1 -LanPort 8080
```

This will:
1. Create a `netsh interface portproxy` rule (0.0.0.0:9119 → 127.0.0.1:9119)
2. Add a Windows Firewall inbound rule for port 9119
3. Detect Hermes and apply the `web_server.py` patch via `git apply`
4. Optionally install a Scheduled Task for dashboard auto-start

### Step 2 — Restart the dashboard

```powershell
hermes dashboard --stop
hermes dashboard --no-open
```

### Step 3 — Verify

```powershell
.\verify.ps1
```

Also test from a LAN device:
```powershell
# From another machine on your network:
curl http://<YOUR_LAN_IP>:9119/api/status
```

---

## What It Creates

### netsh portproxy rule

```powershell
netsh interface portproxy add v4tov4 `
    listenport=9119 listenaddress=0.0.0.0 `
    connectport=9119 connectaddress=127.0.0.1
```

View all portproxy rules:
```powershell
netsh interface portproxy show all
```

### Windows Firewall rule

Name: `Hermes Dashboard (9119)` — inbound, TCP, port 9119, allow.

```powershell
netsh advfirewall firewall show rule name="Hermes Dashboard (9119)"
```

### Scheduled Task (optional)

Name: `Hermes Dashboard` — runs `hermes dashboard --no-open` at user logon
with auto-restart on failure. Registered via `schtasks /create`.

```powershell
schtasks /query /tn "Hermes Dashboard" /fo LIST /v
```

### Hermes web_server.py patch

Same patch as the Linux version — two Python source edits:

1. **CORS regex** (line ~238): Accepts RFC1918 private IP ranges as valid origins
2. **`_is_accepted_host`** (line ~389): When bound to loopback, also accepts
   private LAN IPs in Host/Origin validation

---

## Differences From the Linux Version

| Component | Linux (Fedora) | Windows |
|---|---|---|
| **Port forwarding** | iptables DNAT + nginx | `netsh interface portproxy` |
| **Host header** | Rewritten by nginx → 127.0.0.1 | Accepted directly via the patch |
| **Firewall** | firewalld (iptables/nftables) | `netsh advfirewall` |
| **Auto-start** | systemd (user + system services) | Scheduled Task (schtasks) |
| **SELinux** | semanage + setsebool | ❌ Not applicable |
| **sysctl** | route_localnet=1 | ❌ Not applicable |
| **Extra software** | nginx | ❌ None (uses built-in tools) |

---

## Port Configuration

| Variable | Default | Description |
|---|---|---|
| `LanPort` | `9119` | Port exposed to LAN clients; also the port Hermes listens on at 127.0.0.1 |

Since `netsh portproxy` forwards LAN_PORT → same LAN_PORT at 127.0.0.1, the
dashboard and the LAN port are the same number. Unlike the Linux version,
there's no separate internal port — Windows doesn't have the "same port on
0.0.0.0 vs 127.0.0.1" conflict that Linux does.

---

## Verification Checklist

Run `.\verify.ps1` or check manually:

| Check | Command |
|---|---|
| Portproxy rule | `netsh interface portproxy show v4tov4` |
| Firewall rule | `netsh advfirewall firewall show rule name="Hermes Dashboard (9119)"` |
| Dashboard running | `Get-Process | Where-Object { $_.ProcessName -like "*hermes*" }` |
| Patch applied | `Select-String -Path "$env:USERPROFILE\.hermes\hermes-agent\hermes_cli\web_server.py" -Pattern "192\.168" -Quiet` |
| E2E access | `curl http://127.0.0.1:9119/` |

---

## Rollback

```powershell
# As Administrator:
.\rollback.ps1

# To also revert the Hermes source patches:
cd $env:USERPROFILE\.hermes\hermes-agent
git checkout -- hermes_cli\web_server.py
```

---

## Pitfalls for Windows

| Pitfall | Symptom | Solution |
|---|---|---|
| **Not running as Admin** | "Access denied" on portproxy/firewall | Right-click PowerShell → Run as Administrator |
| **Port already in use** | netsh/firewall rule works but nothing responds | Check `netstat -ano | findstr :9119` |
| **Dashboard not started** | curl to 127.0.0.1:9119 times out | `hermes dashboard --no-open` |
| **Patch not applied** | Browser shows "Invalid Host header" | Apply `patches\allow-lan-origins.patch` manually |
| **No git installed** | Can't apply patch automatically | Use `git apply` manually, or download from GitHub |
| **Windows Defender blocks port** | Firewall rule added but still blocked | Check "Windows Defender Firewall with Advanced Security" |
| **Multiple network adapters** | Portproxy on wrong interface | Add `listenaddress=<specific_LAN_IP>` instead of 0.0.0.0 |
| **WSL/Hyper-V conflicts** | Port 9119 taken by another service | Use `-LanPort` to pick a different port |

---

## Optional: nginx for Windows

If you prefer the same nginx-based approach as Linux:

1. Download nginx for Windows from https://nginx.org/en/download.html
2. Unzip to `C:\nginx\`
3. Copy `config\nginx-hermes-dashboard.conf` to `C:\nginx\conf\conf.d\` (adjust
   the `listen` and `proxy_pass` ports)
4. Run `start nginx` from `C:\nginx\`
5. The netsh portproxy + firewall rules still apply, but point to INTERNAL_PORT

The same `allow-lan-origins.patch` is still required — it handles both modes.

---

## About the Patch

The `patches\allow-lan-origins.patch` file is **identical** to the one in the
Linux package. It patches `hermes_cli/web_server.py` — a Python source file
that is identical across all platforms Hermes supports. One patch, any OS.

```bash
# Same file works on both Linux and Windows:
git apply patches\allow-lan-origins.patch   # Windows
git apply patches/allow-lan-origins.patch   # Linux
```
