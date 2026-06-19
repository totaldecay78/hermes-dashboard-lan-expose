# Hermes Dashboard — LAN Exposure

> **Expose the Hermes Agent dashboard** (bound to `127.0.0.1:9119`) to other
> devices on the local network **without** using `--insecure` or modifying the
> dashboard's bind address.

## 📦 Repository Structure

```
/
├── linux/             ← Fedora/RHEL (dnf, nginx, iptables, firewalld)
│   ├── deploy.sh      ← One-shot infrastructure deploy (run as root)
│   ├── verify.sh      ← Post-deploy verification
│   ├── rollback.sh    ← Clean removal
│   ├── deploy-dashboard-user-service.sh  ← systemd user service auto-start
│   ├── config/        ← Templated nginx, sysctl, systemd service files
│   ├── patches/       ← Git patch for Hermes web_server.py
│   └── README.md      ← Linux-specific instructions
│
├── windows/           ← Windows 8.1+ (PowerShell 5.1, netsh, schtasks)
│   ├── deploy.ps1     ← One-shot infrastructure deploy (run as Admin)
│   ├── verify.ps1     ← Post-deploy verification
│   ├── rollback.ps1   ← Clean removal
│   ├── deploy-dashboard-startup.ps1  ← Scheduled Task auto-start
│   ├── patches/       ← Same git patch (cross-platform Python source)
│   └── README.md      ← Windows-specific instructions
│
└── patches/           ← (symlinked/identical cross-platform patch)
```

## 🎯 For Hermes Agents: Auto-Detection

When a Hermes agent receives the URL of this repo, here is the recommended
workflow:

### Linux agent

```bash
git clone https://github.com/totaldecay78/hermes-dashboard-lan-expose.git
cd hermes-dashboard-lan-expose/linux

# If `uname -s` contains "Linux" — use the bash scripts:
sudo ./deploy.sh

# Apply the web_server.py patch:
cd ~/.hermes/hermes-agent
git apply /path/to/repo/linux/patches/allow-lan-origins.patch

# Verify:
./verify.sh
```

### Windows agent

```powershell
git clone https://github.com/totaldecay78/hermes-dashboard-lan-expose.git
cd hermes-dashboard-lan-expose/windows

# If Microsoft Windows — use the PowerShell scripts:
# (Run as Administrator)
.\deploy.ps1

# Apply the web_server.py patch:
cd $env:USERPROFILE\.hermes\hermes-agent
git apply (Join-Path $PSScriptRoot "patches\allow-lan-origins.patch")

# Verify:
.\verify.ps1
```

### Agent decision tree

```
1. Clone the repo
2. Check [System.Environment]::OSVersion.Platform (Windows)
   OR run `uname -s` (Linux)
3. If Linux → cd linux/ → run deploy.sh
4. If Windows → cd windows/ → run deploy.ps1 (as Admin)
5. Apply patches/allow-lan-origins.patch to Hermes source
6. Restart Hermes dashboard
7. Run verify.sh or verify.ps1
```

## 🧩 What Problem Does This Solve?

The Hermes dashboard listens on `127.0.0.1:9119` by design — only local
processes can reach it. Opening it to 0.0.0.0 via `--insecure` would let
any website read/modify config and secrets.

This package adds a **controlled LAN exposure layer**:

| Layer | Linux | Windows |
|---|---|---|
| Port forwarding | iptables DNAT + nginx | `netsh interface portproxy` |
| Host header adaptation | nginx rewrites → `127.0.0.1` | Patch accepts LAN IPs directly |
| Firewall | firewalld | `netsh advfirewall` |
| Auto-start | systemd user service | Scheduled Task |
| Extra tools | nginx | None (built-in) |

The Hermes `web_server.py` patch (`patches/allow-lan-origins.patch`) is the
same file for both platforms — Python source is cross-platform.

## 🔧 Quick Reference

| Task | Linux | Windows |
|---|---|---|
| Deploy everything | `sudo ./linux/deploy.sh` | `.\windows\deploy.ps1` (Admin) |
| Verify | `./linux/verify.sh` | `.\windows\verify.ps1` (Admin) |
| Rollback | `sudo ./linux/rollback.sh` | `.\windows\rollback.ps1` (Admin) |
| Dashboard auto-start | `./linux/deploy-dashboard-user-service.sh` | `.\windows\deploy-dashboard-startup.ps1` (Admin) |
| Patch web_server.py | `cd ~/.hermes/hermes-agent && git apply linux/patches/allow-lan-origins.patch` | `cd $env:USERPROFILE\.hermes\hermes-agent && git apply windows\patches\allow-lan-origins.patch` |

## 🔐 Security Notes

- **No --insecure**: The dashboard stays on 127.0.0.1. Only the specific
  operations described above allow LAN access.
- **RFC1918 only**: The CORS and Host validation patches only accept private
  IP ranges (10.x.x.x, 172.16-31.x.x, 192.168.x.x). Public/WAN requests are
  still rejected.
- **Local proxy**: On Linux, nginx runs on the same machine and rewrites the
  Host header — LAN browsers never talk directly to the dashboard process.
- **Windows native**: On Windows, netsh portproxy is a kernel-level TCP tunnel
  — no userspace proxy process.
- **Rollback scripts**: Every deploy action has a corresponding rollback.
