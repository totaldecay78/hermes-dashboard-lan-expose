#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Hermes Dashboard LAN Expose — OS auto-detection bootstrap (Windows).
.DESCRIPTION
    Top-level entry point for Windows. Delegates to windows/deploy.ps1.
    Hermes agents: run this at the repo root, it figures out the rest.

    On Linux, use deploy.sh instead.
.PARAMETER LanPort
    Port exposed to LAN clients (default: 9119).
#>

param([int]$LanPort = 9119)

Write-Host "🔧 Detected Windows → delegating to windows/deploy.ps1" -ForegroundColor Cyan
Write-Host ""

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$windowsDeploy = Join-Path $scriptDir "windows\deploy.ps1"

if (-not (Test-Path $windowsDeploy)) {
    Write-Error "windows/deploy.ps1 not found — run this script from the repo root."
    exit 1
}

& $windowsDeploy -LanPort $LanPort
