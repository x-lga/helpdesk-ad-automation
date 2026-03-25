<#
.SYNOPSIS
    Monitors disk space across local drives and emails an alert when below threshold.

.DESCRIPTION
    Runs as a scheduled task. Checks all fixed drives. If any drive is below
    the threshold percentage, sends an email alert to the IT team.

.NOTES
    Schedule via Task Scheduler: Run every 6 hours.
    ITIL 4 alignment: Proactive Event Management — catch issues before users notice.
#>

$ThresholdPct  = 15          # Alert when free space is below 15%
$SmtpServer    = "smtp.contoso.local"
$AlertTo       = "it-alerts@contoso.local"
$AlertFrom     = "monitoring@contoso.local"
$ComputerName  = $env:COMPUTERNAME
$LogFile       = "C:\Logs\DiskMonitor_$(Get-Date -Format 'yyyyMM').log"

if (-not (Test-Path "C:\Logs")) { New-Item -ItemType Directory -Path "C:\Logs" | Out-Null }

function Write-Log {
    param([string]$Message)
    Add-Content -Path $LogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message"
}

$Drives = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Used -gt 0 }

foreach ($Drive in $Drives) {
    $TotalGB   = [math]::Round(($Drive.Used + $Drive.Free) / 1GB, 2)
    $FreeGB    = [math]::Round($Drive.Free / 1GB, 2)
    $FreePct   = [math]::Round(($Drive.Free / ($Drive.Used + $Drive.Free)) * 100, 1)

    Write-Log "Drive $($Drive.Name): Total=${TotalGB}GB | Free=${FreeGB}GB | Free%=${FreePct}%"

    if ($FreePct -lt $ThresholdPct) {
        $Subject = "ALERT: Low Disk Space on $ComputerName — Drive $($Drive.Name) at ${FreePct}% free"
        $Body    = @"
Disk Space Alert — $(Get-Date -Format 'yyyy-MM-dd HH:mm')

Computer : $ComputerName
Drive    : $($Drive.Name)
Total    : ${TotalGB} GB
Free     : ${FreeGB} GB
Free %   : ${FreePct}%
Threshold: ${ThresholdPct}%

Action Required: Review large files, run Disk Cleanup, or escalate for storage expansion.
"@
        try {
            Send-MailMessage -To $AlertTo -From $AlertFrom -Subject $Subject `
                -Body $Body -SmtpServer $SmtpServer
            Write-Log "ALERT SENT: $Subject"
        } catch {
            Write-Log "ERROR: Could not send email — $($_.Exception.Message)"
        }
    }
}
