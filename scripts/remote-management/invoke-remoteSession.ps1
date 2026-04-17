<# **Purpose:** L1 and L2 remote support requires the ability to check a remote machine's
state, run diagnostic commands, or pull log output without establishing a full RDP
session. RDP is slow, requires a licensed session, and disrupts the user. PowerShell
remoting achieves most of the same diagnostic goals in seconds - check a service status,
pull event log entries, restart a process - all without touching the user's screen.
This script handles both modes: interactive remote session (equivalent to PSRemoting
console) and one-off command execution (run a single command and return the output).#>

```powershell
<#
.SYNOPSIS
    Opens a remote PowerShell session or executes a single command on a remote machine.

.DESCRIPTION
    Two modes of operation:
      Interactive mode (no -Command): Opens an Enter-PSSession to the target machine.
                                      The technician gets a full remote console.
      Command mode (-Command provided): Runs the specified command remotely and returns
                                        output. Useful for quick diagnostics without
                                        entering an interactive session.

    Pre-flight check: Tests network connectivity before attempting remote connection,
    providing a clear error if the machine is unreachable rather than a confusing timeout.

.PARAMETER ComputerName
    Hostname or IP address of the target machine.

.PARAMETER Command
    Optional. A single PowerShell command or expression to execute remotely.
    If omitted, an interactive remote session is opened.

.EXAMPLE
    # Open interactive session to PC001
    .\Invoke-RemoteSession.ps1 -ComputerName PC001

    # Check the Windows Update service on PC001 without entering interactive session
    .\Invoke-RemoteSession.ps1 -ComputerName PC001 -Command "Get-Service wuauserv | Select-Object Name, Status"

    # Pull the last 10 system event log errors remotely
    .\Invoke-RemoteSession.ps1 -ComputerName SERVER01 -Command "Get-EventLog -LogName System -EntryType Error -Newest 10 | Select-Object TimeGenerated, Source, Message"

.NOTES
    Requires  : WinRM enabled on the target machine (enabled by default on Server OSes,
                requires: winrm quickconfig on Windows 10/11 clients)
    Run as    : Account with local admin rights on the target machine
    Cert align: CompTIA A+, CompTIA Network+
#>

param(
    [Parameter(Mandatory = $true, HelpMessage = "Computer name or IP address of target machine")]
    [string]$ComputerName,

    [Parameter(Mandatory = $false, HelpMessage = "Single command to execute remotely (optional)")]
    [string]$Command = ""
)

# ─────────────────────────────────────────────────────────────
#  PRE-FLIGHT: CONNECTIVITY CHECK
# ─────────────────────────────────────────────────────────────
Write-Host "`nTesting connectivity to $ComputerName..." -ForegroundColor Cyan

if (-not (Test-Connection -ComputerName $ComputerName -Count 2 -Quiet)) {
    Write-Host "`n[ERROR] Cannot reach $ComputerName via ping." -ForegroundColor Red
    Write-Host "Possible causes:" -ForegroundColor Yellow
    Write-Host "  - Machine is powered off" -ForegroundColor Yellow
    Write-Host "  - Machine name is incorrect (check AD for exact name)" -ForegroundColor Yellow
    Write-Host "  - ICMP blocked by Windows Firewall on target machine" -ForegroundColor Yellow
    Write-Host "  - Network connectivity issue between your machine and target" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "If ping is blocked by policy, test WinRM directly:" -ForegroundColor Cyan
    Write-Host "  Test-NetConnection -ComputerName $ComputerName -Port 5985" -ForegroundColor Cyan
    exit 1
}

Write-Host "  Connectivity: OK" -ForegroundColor Green

# ─────────────────────────────────────────────────────────────
#  EXECUTE
# ─────────────────────────────────────────────────────────────
if ($Command) {
    # Mode: single command execution
    Write-Host "  Mode: Remote command execution" -ForegroundColor Cyan
    Write-Host "  Command: $Command" -ForegroundColor DarkGray
    Write-Host "  Target : $ComputerName" -ForegroundColor DarkGray
    Write-Host ""

    try {
        $Result = Invoke-Command -ComputerName $ComputerName -ScriptBlock {
            param($Cmd)
            Invoke-Expression $Cmd
        } -ArgumentList $Command -ErrorAction Stop

        Write-Host "── Remote Output from $ComputerName ──" -ForegroundColor Cyan
        $Result | Format-Table -AutoSize
        Write-Host "── End of output ──" -ForegroundColor Cyan

    } catch {
        Write-Host "`n[ERROR] Remote command failed: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Check that WinRM is running on $ComputerName and your account has admin rights." -ForegroundColor Yellow
    }

} else {
    # Mode: interactive session
    Write-Host "  Mode: Interactive remote session" -ForegroundColor Cyan
    Write-Host "  Connecting to $ComputerName..." -ForegroundColor Cyan
    Write-Host "  Type 'Exit-PSSession' or press Ctrl+C to return to local machine." -ForegroundColor Yellow
    Write-Host ""

    try {
        Enter-PSSession -ComputerName $ComputerName -ErrorAction Stop
    } catch {
        Write-Host "`n[ERROR] Could not open remote session: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Ensure WinRM is configured: run 'winrm quickconfig' on $ComputerName" -ForegroundColor Yellow
    }
}
