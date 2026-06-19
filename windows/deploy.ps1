<#:
.SYNOPSIS
    Expose the Hermes Agent dashboard to LAN devices on Windows.
.DESCRIPTION
    Deploys everything needed to access the Hermes dashboard (127.0.0.1:9119)
    from other devices on the local network without --insecure.

    Uses Windows-native tools:
      - netsh interface portproxy  → port forwarding (0.0.0.0 -> 127.0.0.1)
      - netsh advfirewall          → Windows Firewall rule
      - schtasks                   → Scheduled Task for dashboard auto-start

    The Hermes web_server.py patch (same as Linux) handles CORS + Host
    validation for LAN IPs. No nginx or extra software needed.

.PARAMETER LanPort
    Port exposed to LAN clients (default: 9119).

.PARAMETER DashboardPort
    Port Hermes dashboard listens on at 127.0.0.1 (default: same as LanPort).

.EXAMPLE
    # Deploy with defaults (9119)
    .\deploy.ps1

.EXAMPLE
    # Custom port
    .\deploy.ps1 -LanPort 8080

.NOTES
    Run as Administrator — requires elevation for portproxy + firewall rules.
#>

param(
    [int]$LanPort = 9119,
    [int]$DashboardPort = $LanPort
)

#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigDir = Join-Path $ScriptDir "config"
$PatchesDir = Join-Path $ScriptDir "patches"

# ---- Colour helpers (PS 5.1 compatible) ----
function Write-Info  { Write-Host " ℹ️  $args" -ForegroundColor Cyan }
function Write-Step  { Write-Host " 🔧 $args" -ForegroundColor Yellow }
function Write-Done  { Write-Host " ✅ $args" -ForegroundColor Green }
function Write-Warn  { Write-Host " ⚠️  $args" -ForegroundColor Magenta }
function Write-Err   { Write-Host " ❌ $args" -ForegroundColor Red }

Write-Host "===========================================" -ForegroundColor Cyan
Write-Host " Hermes Dashboard — LAN Expose (Windows)" -ForegroundColor Cyan
Write-Host "===========================================" -ForegroundColor Cyan
Write-Host ""
Write-Info "LAN access port . . : $LanPort"
Write-Info "Dashboard port . . . : $DashboardPort (127.0.0.1)"
Write-Info ""

# ---- 1. Check if portproxy rule already exists ----
$ExistingProxy = netsh interface portproxy show v4tov4 2>$null |
    Select-String "0.0.0.0.*$LanPort"
if ($ExistingProxy) {
    Write-Warn "Portproxy rule for 0.0.0.0:$LanPort already exists — skipping"
}
else {
    Write-Step "Adding netsh portproxy: 0.0.0.0:$LanPort → 127.0.0.1:$DashboardPort ..."
    netsh interface portproxy add v4tov4 `
        listenport=$LanPort listenaddress=0.0.0.0 `
        connectport=$DashboardPort connectaddress=127.0.0.1
    if ($LASTEXITCODE -eq 0) {
        Write-Done "Portproxy rule added"
    }
    else {
        Write-Err "Portproxy failed (exit code $LASTEXITCODE)"
        exit 1
    }
}

# ---- 2. Windows Firewall rule ----
$FwRuleName = "Hermes Dashboard ($LanPort)"
$ExistingFw = netsh advfirewall firewall show rule name="$FwRuleName" 2>$null |
    Select-String "Rule Name:.*$FwRuleName"
if ($ExistingFw) {
    Write-Warn "Firewall rule '$FwRuleName' already exists — skipping"
}
else {
    Write-Step "Adding Windows Firewall rule '$FwRuleName' ..."
    netsh advfirewall firewall add rule `
        name="$FwRuleName" dir=in protocol=tcp localport=$LanPort action=allow
    if ($LASTEXITCODE -eq 0) {
        Write-Done "Firewall rule added"
    }
    else {
        Write-Err "Firewall rule failed (exit code $LASTEXITCODE)"
        exit 1
    }
}

# ---- 3. Patch Hermes web_server.cs (Python source, OS-independent) ----
Write-Step "Checking Hermes web_server.py for LAN origin support ..."
$HermesDirs = @(
    "$env:USERPROFILE\.hermes\hermes-agent",
    "$env:LOCALAPPDATA\hermes\hermes-agent"
)
$WebServerPath = $null
foreach ($d in $HermesDirs) {
    $testPath = Join-Path $d "hermes_cli\web_server.py"
    if (Test-Path $testPath) {
        $WebServerPath = $testPath
        break
    }
}
if (-not $WebServerPath) {
    # Try PATH lookup
    $which = Get-Command "hermes" -ErrorAction SilentlyContinue
    if ($which) {
        $hermesDir = Split-Path (Split-Path $which.Source -Parent) -Parent
        $testPath = Join-Path $hermesDir "hermes_cli\web_server.py"
        if (Test-Path $testPath) { $WebServerPath = $testPath }
    }
}
if (-not $WebServerPath) {
    Write-Warn "Could not find web_server.py automatically."
    Write-Warn "Apply the patch manually after locating Hermes:"
    Write-Warn "  cd <hermes-agent-dir>"
    Write-Warn "  git apply '$PatchesDir\allow-lan-origins.patch'"
}
else {
    Write-Info "Found web_server.py at: $WebServerPath"
    $AlreadyPatched = Select-String -Path $WebServerPath -Pattern "192\.168" -Quiet
    if ($AlreadyPatched) {
        Write-Done "web_server.py already patched for LAN access"
    }
    else {
        $HermesRepo = Split-Path (Split-Path $WebServerPath -Parent) -Parent
        $PatchFile = Join-Path $PatchesDir "allow-lan-origins.patch"
        if (Test-Path $PatchFile) {
            $hasGit = Get-Command "git" -ErrorAction SilentlyContinue
            if ($hasGit) {
                Push-Location $HermesRepo
                git apply "$PatchFile" 2>$null
                $applyResult = $LASTEXITCODE
                Pop-Location
                if ($applyResult -eq 0) {
                    Write-Done "Patch applied successfully"
                }
                else {
                    Write-Warn "git apply failed (may need manual resolution)."
                    Write-Warn "Try: cd $HermesRepo && git apply '$PatchFile'"
                }
            }
            else {
                Write-Warn "Git not found. Apply the patch manually:"
                Write-Warn "  1. Open $WebServerPath"
                Write-Warn "  2. Replace CORS regex and _is_accepted_host"
                Write-Warn "     (see $PatchFile for the exact diff)"
            }
        }
        else {
            Write-Warn "Patch file not found at $PatchFile"
        }
    }
}

# ---- 4. Offer Scheduled Task for dashboard auto-start ----
Write-Host ""
Write-Step "Dashboard auto-start at boot?"
$choice = Read-Host "Install Scheduled Task to auto-start Hermes dashboard? [Y/n] "
if ($choice -eq "" -or $choice -match "^[Yy]") {
    & (Join-Path $ScriptDir "deploy-dashboard-startup.ps1") -LanPort $LanPort
}

Write-Host ""
Write-Done "Deploy complete!"
Write-Host ""
Write-Info "Next steps:"
Write-Info "  1. If the patch was applied, restart Hermes dashboard:"
    Write-Info "     hermes dashboard --stop"
Write-Info "     hermes dashboard --no-open"
Write-Info "  2. Test from a LAN device:"
Write-Info "     curl http://<YOUR_LAN_IP>:$LanPort/api/status"
Write-Info "  3. Run verification:"
Write-Info "     .\verify.ps1 -LanPort $LanPort"
Write-Host ""
