---
name: hermes-dashboard-lan-expose
description: "Expose the Hermes Agent dashboard (127.0.0.1:9119) to other devices on your LAN — cross-platform (Linux + Windows) with nginx, iptables, firewalld, netsh portproxy, and verified rollback."
version: 1.0.0
author: totaldecay78
license: MIT
platforms: [linux, windows]
metadata:
  hermes:
    tags:
      - hermes
      - dashboard
      - lan
      - network
      - expose
      - nginx
      - iptables
      - portproxy
      - netsh
      - systemd
      - firewall
      - remote-access
      - port-forwarding
      - cross-platform
      - linux
      - windows
      - self-hosted
    homepage: https://github.com/totaldecay78/hermes-dashboard-lan-expose
    related_skills: [hermes-agent, hermes-dashboard-lan-expose, debugging-hermes-tui-commands]
---

# Hermes Dashboard — LAN Exposure

> **Give your Hermes Dashboard LAN access** — reach `http://192.168.x.x:9191` from any device on your local network, without `--insecure` or modifying the dashboard's safe `127.0.0.1` bind address.

## When to Use This Skill

A Hermes agent should load this skill when:

- The user asks to **access the Hermes dashboard from another device** on the network (phone, tablet, laptop)
- The user asks to **expose the dashboard to the LAN**
- The user needs **remote access to the Hermes web UI** without using `--insecure`
- The user is on **Linux (Fedora/RHEL)** or **Windows 8.1+** and needs network setup
- The user mentions **nginx, iptables, netsh, portproxy, firewalld, or port forwarding** in context of the Hermes dashboard
- The user asks about **dashboard auto-start on boot** via systemd or Scheduled Tasks

## How It Works

The Hermes dashboard listens on `127.0.0.1:9119` — localhost only, safe by default. This skill adds a **controlled LAN exposure layer** that keeps the dashboard on localhost while making it reachable via a second port.

| Layer | Linux | Windows |
|-------|-------|---------|
| Port forwarding | nginx (port 9191→9119) + iptables DNAT | `netsh interface portproxy` |
| Host header fix | nginx rewrites Host → `127.0.0.1` | Patch accepts LAN IPs directly |
| Firewall | firewalld | `netsh advfirewall` |
| Auto-start | systemd user service | Scheduled Task |
| Web server | nginx (dnf package) | Built-in (no extra install) |
| Rollback | `rollback.sh` | `rollback.ps1` |

## Agent Workflow

When a user asks you to set up LAN dashboard access:

### 1. Clone the repo

```bash
git clone https://github.com/totaldecay78/hermes-dashboard-lan-expose.git
cd hermes-dashboard-lan-expose
```

### 2. Detect OS

```bash
# Linux
uname -s   # → "Linux"

# Windows (from PowerShell)
[System.Environment]::OSVersion.Platform  # → "Win32NT"
```

### 3. Deploy

**Linux (Fedora/RHEL):**
```bash
cd linux
sudo ./deploy.sh              # Set up nginx, iptables, firewalld
./deploy-dashboard-user-service.sh  # systemd auto-start
```

**Windows (8.1+, PowerShell Admin):**
```powershell
cd windows
.\deploy.ps1                  # Set up portproxy, firewall rules
.\deploy-dashboard-startup.ps1  # Scheduled Task auto-start
```

### 4. Patch web_server.py (cross-platform)

The Hermes source needs one patch to accept LAN-origin requests:

```bash
cd ~/.hermes/hermes-agent
git apply /path/to/repo/patches/allow-lan-origins.patch
```

This is the **same patch for both platforms** — Python source is cross-platform.

### 5. Restart dashboard and verify

```bash
# Linux
systemctl --user restart hermes-dashboard
./linux/verify.sh

# Windows
Restart-Service HermesDashboard  # or restart the process
.\windows\verify.ps1
```

### 6. Access from LAN

Open `http://192.168.x.x:9191` from any device on your local network.

## Security Model

- **No `--insecure`**: The dashboard stays on `127.0.0.1`. Only the specific operations above allow LAN access.
- **RFC1918 only**: CORS and Host validation only accept private IPs (10.x.x.x, 172.16-31.x.x, 192.168.x.x).
- **Local proxy** (Linux): nginx runs on the same machine, rewrites the Host header — LAN browsers never talk directly to the dashboard.
- **Kernel-level** (Windows): `netsh portproxy` is a TCP tunnel in the TCP/IP stack — no userspace proxy process.
- **Full rollback**: Every deploy action has a corresponding rollback script.

## Platform-Specific Details

### Linux
- Requires: `dnf`, `nginx`, `iptables`, `firewalld`, `systemctl`
- Architecture: nginx reverse proxy (9191) → iptables DNAT → dashboard (9119)
- Firewall: firewalld opens port 9191/tcp for the LAN zone
- Auto-start: systemd user service (`hermes-dashboard-lan-expose.service`)
- Rollback: removes nginx config, iptables rules, firewall rules, and systemd service

### Windows
- Requires: PowerShell 5.1+, Admin privileges
- Architecture: `netsh interface portproxy` (9191) → dashboard (9119) via IP helper
- Firewall: `netsh advfirewall` opens port 9191/tcp
- Auto-start: Scheduled Task (run at logon)
- Rollback: removes portproxy, firewall rule, and scheduled task

## File Reference

| File | Purpose |
|------|---------|
| `linux/deploy.sh` | One-shot Linux deploy (root) |
| `linux/verify.sh` | Post-deploy connectivity check |
| `linux/rollback.sh` | Clean removal (reverse of deploy) |
| `linux/deploy-dashboard-user-service.sh` | systemd auto-start |
| `linux/config/` | nginx, sysctl, systemd templates |
| `windows/deploy.ps1` | One-shot Windows deploy (Admin) |
| `windows/verify.ps1` | Post-deploy connectivity check |
| `windows/rollback.ps1` | Clean removal |
| `windows/deploy-dashboard-startup.ps1` | Scheduled Task auto-start |
| `patches/allow-lan-origins.patch` | Cross-platform web_server.py patch |

## Troubleshooting

**"Connection refused" from LAN device:**
1. Check the dashboard is running: `systemctl --user status hermes-dashboard` (Linux) or `Get-Process hermes*` (Windows)
2. Check the proxy: `curl -s http://127.0.0.1:9191` from the host
3. Check the firewall: `sudo firewall-cmd --list-all` (Linux) or `netsh advfirewall firewall show rule name=all` (Windows)
4. Verify the patch was applied: the dashboard logs should show accepted LAN origins
5. Run the verify script for your platform

**Dashboard doesn't start after reboot (Linux):**
Run `./linux/deploy-dashboard-user-service.sh` to install the systemd user service, then enable lingering: `sudo loginctl enable-linger $USER`.

**Dashboard doesn't start after reboot (Windows):**
Run `.\windows\deploy-dashboard-startup.ps1` (as Admin) to create the Scheduled Task. Check Task Scheduler → Task Scheduler Library → `HermesDashboard`.
