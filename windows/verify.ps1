#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Verify the Hermes Dashboard LAN Expose setup on Windows.
.DESCRIPTION
    Checks: netsh portproxy, Windows Firewall, Scheduled Task,
    Hermes web_server.py patch, and end-to-end dashboard access.
.PARAMETER LanPort
    Port exposed to LAN clients (default: 9119).
#>

param([int]$LanPort = 9119)

$global:Pass = 0; $global:Fail = 0; $global:Warn = 0

function Check($Desc, $ScriptBlock) {
    if (& $ScriptBlock) {
        Write-Host "  ✅ $Desc" -ForegroundColor Green
        $global:Pass++
    }
    else {
        Write-Host "  ❌ $Desc" -ForegroundColor Red
        $global:Fail++
    }
}

function Warn($Desc, $Msg) {
    Write-Host "  ⚠️  $Desc" -ForegroundColor Magenta
    Write-Host "     $Msg"
    $global:Warn++
}

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " Hermes Dashboard LAN — Verification" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# --- 1. netsh portproxy ---
Write-Host "📡 netsh portproxy:" -ForegroundColor Yellow
$proxyList = netsh interface portproxy show v4tov4
Check "Portproxy $LanPort -> 127.0.0.1" {
    $proxyList -match "0\.0\.0\.0.*$LanPort.*127\.0\.0\.1.*$LanPort"
}

# --- 2. Windows Firewall ---
Write-Host ""
Write-Host "🔥 Windows Firewall:" -ForegroundColor Yellow
$fwName = "Hermes Dashboard ($LanPort)"
$fwRule = netsh advfirewall firewall show rule name="$fwName" 2>$null
Check "Firewall rule '$fwName' exists" { $fwRule -match "Rule Name:" }
Check "Firewall rule is enabled" { $fwRule -match "Enabled:.*Yes" }
Check "TCP port $LanPort allowed inbound" { $fwRule -match "LocalPort:.*$LanPort" }

# --- 3. Scheduled Task ---
$taskName = "Hermes Dashboard"
$task = schtasks /query /tn "$taskName" /fo LIST /v 2>$null
Write-Host ""
Write-Host "⚙️  Scheduled Task:" -ForegroundColor Yellow
if ($task -match "$taskName") {
    $enabled = $task -match "Status:.*Ready|Running"
    Check "Scheduled Task '$taskName' exists" { $true }
    if ($enabled) { Write-Host "  ✅ Task is enabled" -ForegroundColor Green; $global:Pass++ }
    else { Warn "Task exists but may be disabled" ""; $global:Warn++ }
}
else {
    Warn "Scheduled Task '$taskName' not found" "Run .\deploy-dashboard-startup.ps1 to create it"
}

# --- 4. Hermes web_server.py patch ---
Write-Host ""
Write-Host "🔧 Hermes web_server.py patches:" -ForegroundColor Yellow
$hermesDirs = @(
    "$env:USERPROFILE\.hermes\hermes-agent",
    "$env:LOCALAPPDATA\hermes\hermes-agent"
)
$webServer = $null
foreach ($d in $hermesDirs) {
    $p = Join-Path $d "hermes_cli\web_server.py"
    if (Test-Path $p) { $webServer = $p; break }
}
if ($webServer) {
    Check "CORS regex includes RFC1918" {
        Select-String -Path $webServer -Pattern "192\.168" -Quiet
    }
    Check "_is_accepted_host patched" {
        Select-String -Path $webServer -Pattern "RFC1918|172\.\(1\[6-9\]" -Quiet
    }
}
else {
    Warn "web_server.py not found" "Set HERMES_HOME or check installation"
}

# --- 5. End-to-end ---
Write-Host ""
Write-Host "📡 End-to-end test:" -ForegroundColor Yellow
try {
    $req = [System.Net.WebRequest]::Create("http://127.0.0.1:$LanPort/")
    $req.Timeout = 3000
    $resp = $req.GetResponse()
    $code = [int]$resp.StatusCode
    if ($code -ge 200 -and $code -le 399) {
        Write-Host "  ✅ Dashboard accessible via 127.0.0.1:$LanPort (HTTP $code)" -ForegroundColor Green
        $global:Pass++
    }
    else {
        Write-Host "  ❌ Dashboard returned HTTP $code" -ForegroundColor Red
        $global:Fail++
    }
    $resp.Close()
}
catch {
    Write-Host "  ❌ Dashboard NOT accessible via 127.0.0.1:$LanPort" -ForegroundColor Red
    Write-Host "     $_" -ForegroundColor DarkGray
    $global:Fail++
}

# --- Summary ---
Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " Results: $($global:Pass) passed, $($global:Fail) failed, $($global:Warn) warnings" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

if ($global:Fail -gt 0) { exit 1 }
