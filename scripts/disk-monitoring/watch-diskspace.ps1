<# **Purpose:** Disk space exhaustion causes application crashes, failed backup jobs, event
log truncation, and service outages - all of which are preventable with proactive monitoring.
Most IT teams discover a full disk when a user reports something broken, by which point
the damage is done. This script is designed to run as a Windows Scheduled Task every
4-6 hours. It checks all fixed drives on the local machine, calculates free percentage,
and sends a structured email alert the moment any drive drops below the configured threshold.
The alert includes enough information for the on-call technician to act without needing to
RDP into the machine first.

ITIL 4 alignment: This script operationalises Event Management - the ITIL 4 practice of
detecting and responding to events (significant status changes) before they become Incidents.
Catching disk at 14% free is an Event. The same drive at 0% causing a service crash is
a P1 Incident. One scheduled task prevents the other.#>

```powershell
<#
.SYNOPSIS
    Monitors disk space on all local fixed drives and sends an email alert
    when any drive drops below the configured threshold.

.DESCRIPTION
    Designed for deployment as a Windows Scheduled Task.
    Recommended schedule: every 4–6 hours, run as a service account.

    For each fixed drive the script:
      - Calculates total size, used space, free space, and free percentage
      - Logs the reading with timestamp regardless of alert status (trend data)
      - Sends a detailed email alert if free percentage is below threshold
      - Email includes drive details, recommended L1 actions, and server name

    The email alert is structured so the on-call technician has everything they need
    to take immediate action without needing to connect to the server first.

    ITIL 4 alignment: Proactive Event Management — converts reactive P1 incidents
    (disk full, service crashed) into manageable P3 events (disk approaching threshold).

.NOTES
    Schedule  : Task Scheduler → every 4–6 hours → run as service account
    Configure : Update $SmtpServer, $AlertTo, $AlertFrom, $ThresholdPct below
    Cert align: CompTIA A+, ITIL 4 Event Management
#>

# ─────────────────────────────────────────────────────────────
#  CONFIGURATION — update these for your environment
# ─────────────────────────────────────────────────────────────
$ThresholdPct = 15           # Alert when free space drops below this percentage
$SmtpServer   = "smtp.contoso.local"
$AlertTo      = "it-alerts@contoso.local"
$AlertFrom    = "monitoring@contoso.local"
$ComputerName = $env:COMPUTERNAME

$LogDir  = "C:\Logs\DiskMonitor"
$LogFile = "$LogDir\DiskMonitor_$(Get-Date -Format 'yyyyMM').log"  # Monthly log file

# ─────────────────────────────────────────────────────────────
#  LOGGING
# ─────────────────────────────────────────────────────────────
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $Entry = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level] [$ComputerName] $Message"
    Add-Content -Path $LogFile -Value $Entry
}

Write-Log "Disk monitoring check started."

# ─────────────────────────────────────────────────────────────
#  CHECK ALL FIXED DRIVES
# ─────────────────────────────────────────────────────────────
$Drives = Get-PSDrive -PSProvider FileSystem | Where-Object {
    $_.Used -gt 0 -and $_.Name.Length -eq 1  # Fixed drives only (single letter = local)
}

foreach ($Drive in $Drives) {
    $TotalGB  = [math]::Round(($Drive.Used + $Drive.Free) / 1GB, 2)
    $UsedGB   = [math]::Round($Drive.Used / 1GB, 2)
    $FreeGB   = [math]::Round($Drive.Free / 1GB, 2)
    $FreePct  = [math]::Round(($Drive.Free / ($Drive.Used + $Drive.Free)) * 100, 1)

    Write-Log "Drive $($Drive.Name): Total=${TotalGB}GB | Used=${UsedGB}GB | Free=${FreeGB}GB | Free%=${FreePct}%"

    if ($FreePct -lt $ThresholdPct) {
        Write-Log "ALERT: Drive $($Drive.Name) at ${FreePct}% free — BELOW threshold of ${ThresholdPct}%." "WARN"

        $AlertSubject = "⚠ LOW DISK SPACE: $ComputerName — Drive $($Drive.Name): ${FreePct}% free"
        $AlertBody    = @"
DISK SPACE ALERT
════════════════════════════════════════════
Generated  : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Server     : $ComputerName
Drive      : $($Drive.Name):\
Total      : ${TotalGB} GB
Used       : ${UsedGB} GB
Free       : ${FreeGB} GB  ← ${FreePct}% remaining
Threshold  : ${ThresholdPct}%
════════════════════════════════════════════

RECOMMENDED L1 ACTIONS (attempt in order):

1. Run Disk Cleanup:
   Start → Run → cleanmgr.exe
   Select all categories including System files

2. Clear Windows Update cache:
   net stop wuauserv
   del /q /f /s C:\Windows\SoftwareDistribution\Download\*
   net start wuauserv

3. Clear Temp folders:
   del /q /f /s C:\Windows\Temp\*
   del /q /f /s %TEMP%\*

4. Find large files with PowerShell:
   Get-ChildItem C:\ -Recurse -ErrorAction SilentlyContinue |
     Sort-Object Length -Descending |
     Select-Object -First 20 FullName, @{N='SizeMB';E={[math]::Round($_.Length/1MB,2)}}

5. Check for oversized log files:
   Common locations: C:\inetpub\logs, C:\Windows\Logs, application-specific log dirs

6. ESCALATE if above steps do not resolve below threshold:
   Document current free space, steps taken, and largest files found.
   L2 will evaluate storage expansion, archiving, or cleanup policies.

════════════════════════════════════════════
This alert was generated automatically by the disk monitoring scheduled task.
Do not reply to this message. Log into $ComputerName to investigate.
"@

        try {
            Send-MailMessage -To $AlertTo -From $AlertFrom -Subject $AlertSubject `
                -Body $AlertBody -SmtpServer $SmtpServer -ErrorAction Stop
            Write-Log "Alert email sent to $AlertTo for Drive $($Drive.Name)." "SUCCESS"
        } catch {
            Write-Log "ERROR: Failed to send alert email. SmtpServer: $SmtpServer. Error: $($_.Exception.Message)" "ERROR"
        }
    }
}

Write-Log "Disk monitoring check completed."
