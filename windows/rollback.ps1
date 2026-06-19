#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Remove every change made by deploy.ps1 on Windows.
.DESCRIPTION
    Cleans up: netsh portproxy, Windows Firewall rule, Scheduled Task.
    Does NOT revert the web_server.py patch (use git checkout for that).
.PARAMETER LanPort
    Port that was exposed to LAN (default: 9119).
#>

param([int]$LanPort = 9119)

$ErrorActionPreference = "Continue"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

function Write-Step  { Write-Host " 🔧 $args" -ForegroundColor Yellow }
function Write-Done  { Write-Host " ✅ $args" -ForegroundColor Green }

Write-Host "🧹 Hermes Dashboard LAN Expose — Rollback (Windows)" -ForegroundColor Cyan
Write-Host ""

# --- 1. Remove netsh portproxy ---
Write-Step "Removing netsh portproxy (0.0.0.0:$LanPort) ..."
netsh interface portproxy delete v4tov4 listenport=$LanPort listenaddress=0.0.0.0
Write-Done "Portproxy removed"

# --- 2. Remove Firewall rule ---
Write-Step "Removing Windows Firewall rule 'Hermes Dashboard ($LanPort)' ..."
netsh advfirewall firewall delete rule name="Hermes Dashboard ($LanPort)" 2>$null
Write-Done "Firewall rule removed"

# --- 3. Remove Scheduled Task ---
Write-Step "Removing Scheduled Task 'Hermes Dashboard' ..."
schtasks /end /tn "Hermes Dashboard" 2>$null
schtasks /delete /tn "Hermes Dashboard" /f 2>$null
Write-Done "Scheduled Task removed"

Write-Host ""
Write-Done "Rollback complete!"
Write-Host ""
Write-Host "To revert the Hermes web_server.py patches:" -ForegroundColor Yellow
Write-Host "  cd %USERPROFILE%\.hermes\hermes-agent" -ForegroundColor Gray
Write-Host "  git checkout -- hermes_cli\web_server.py" -ForegroundColor Gray
Write-Host ""
Write-Host "Then restart the dashboard:" -ForegroundColor Yellow
Write-Host "  hermes dashboard --stop" -ForegroundColor Gray
Write-Host "  hermes dashboard --no-open" -ForegroundColor Gray
