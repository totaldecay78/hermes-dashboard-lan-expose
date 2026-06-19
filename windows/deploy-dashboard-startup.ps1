#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Install Hermes Dashboard as a Windows Scheduled Task for auto-start.
.DESCRIPTION
    Creates a Scheduled Task that starts the Hermes Agent dashboard
    at user logon and restarts it if it crashes.
    Uses schtasks.exe for maximum PowerShell 5.1 compatibility.
.PARAMETER LanPort
    Dashboard port (default: 9119).
#>

param([int]$LanPort = 9119)

$ErrorActionPreference = "Stop"

function Write-Step  { Write-Host " 🔧 $args" -ForegroundColor Yellow }
function Write-Done  { Write-Host " ✅ $args" -ForegroundColor Green }
function Write-Info  { Write-Host " ℹ️  $args" -ForegroundColor Cyan }
function Write-Warn  { Write-Host " ⚠️  $args" -ForegroundColor Magenta }

Write-Host "🔧 Hermes Dashboard — Scheduled Task Install (Windows)" -ForegroundColor Cyan
Write-Host ""

# --- Detect Hermes dashboard executable ---
$hermesExe = $null

# Check PATH
$which = Get-Command "hermes" -ErrorAction SilentlyContinue
if ($which) {
    $hermesExe = $which.Source
}

# Check standard locations
if (-not $hermesExe) {
    $pathsToCheck = @(
        "$env:USERPROFILE\.hermes\hermes-agent\venv\Scripts\hermes.exe",
        "$env:USERPROFILE\.hermes\hermes-agent\venv\Scripts\hermes",
        "$env:LOCALAPPDATA\hermes\hermes-agent\venv\Scripts\hermes.exe",
        "$env:LOCALAPPDATA\hermes\hermes-agent\venv\Scripts\hermes"
    )
    foreach ($p in $pathsToCheck) {
        if (Test-Path $p) { $hermesExe = $p; break }
    }
}

if (-not $hermesExe) {
    Write-Warn "Could not find Hermes executable."
    $hermesExe = Read-Host "Enter full path to Hermes executable (e.g. C:\Users\you\.hermes\hermes-agent\venv\Scripts\hermes.exe)"
    if (-not (Test-Path $hermesExe)) {
        Write-Error "File not found: $hermesExe"
        exit 1
    }
}

$hermesDir = Split-Path $hermesExe -Parent
$hermesHome = $env:HERMES_HOME
if (-not $hermesHome) { $hermesHome = "$env:USERPROFILE\.hermes" }

Write-Info "Hermes exe : $hermesExe"
Write-Info "Hermes home: $hermesHome"
Write-Info "Dashboard  : 127.0.0.1:$LanPort"
Write-Info ""

# --- Create the Scheduled Task XML ---
$taskName = "Hermes Dashboard"
$taskXml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>Hermes Agent Dashboard - Web UI</Description>
  </RegistrationInfo>
  <Triggers>
    <LogonTrigger>
      <Enabled>true</Enabled>
      <Delay>PT10S</Delay>
    </LogonTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>$([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)</UserId>
      <LogonType>InteractiveToken</LogonType>
      <RunLevel>LeastPrivilege</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>true</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>true</RunOnlyIfNetworkAvailable>
    <IdleSettings>
      <StopOnIdleEnd>false</StopOnIdleEnd>
      <RestartOnIdle>false</RestartOnIdle>
    </IdleSettings>
    <RestartOnFailure>
      <Interval>PT1M</Interval>
      <Count>999</Count>
    </RestartOnFailure>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>$hermesExe</Command>
      <Arguments>dashboard --no-open</Arguments>
      <WorkingDirectory>$hermesHome</WorkingDirectory>
    </Exec>
  </Actions>
</Task>
"@

# --- Register the task ---
$tempXml = [System.IO.Path]::GetTempFileName() + ".xml"
try {
    [System.IO.File]::WriteAllText($tempXml, $taskXml, [System.Text.Encoding]::Unicode)
    Write-Step "Registering Scheduled Task '$taskName' ..."

    $result = schtasks /create /tn "$taskName" /xml "$tempXml" /f 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Done "Scheduled Task registered: '$taskName'"
        Write-Info "The dashboard will start automatically at next logon."

        # Offer to start it now
        $startNow = Read-Host "Start the dashboard now? [Y/n] "
        if ($startNow -eq "" -or $startNow -match "^[Yy]") {
            schtasks /run /tn "$taskName"
            Write-Done "Dashboard started! (check with: schtasks /query /tn '$taskName' /fo LIST /v)"
        }
    }
    else {
        Write-Error "schtasks failed: $result"
        exit 1
    }
}
finally {
    if (Test-Path $tempXml) { Remove-Item $tempXml -Force }
}
