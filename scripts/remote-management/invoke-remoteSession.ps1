<#
.SYNOPSIS
    Opens a remote PowerShell session or runs a command on a remote machine.

.DESCRIPTION
    L1/L2 remote management script. Supports both interactive sessions and
    one-off remote command execution. Useful for checking status, running
    scripts, or pulling logs without RDP.

.PARAMETER ComputerName
    Target computer name or IP address.

.PARAMETER Command
    Optional one-liner to run remotely. If omitted, opens interactive session.

.EXAMPLE
    .\Invoke-RemoteSession.ps1 -ComputerName PC001
    .\Invoke-RemoteSession.ps1 -ComputerName PC001 -Command "Get-Service wuauserv"
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$ComputerName,

    [string]$Command = ""
)

# Test connectivity first
if (-not (Test-Connection -ComputerName $ComputerName -Count 2 -Quiet)) {
    Write-Host "ERROR: Cannot reach $ComputerName. Check network connectivity or machine status." -ForegroundColor Red
    exit 1
}

Write-Host "Connecting to $ComputerName..." -ForegroundColor Cyan

if ($Command) {
    # Run a single command remotely
    Invoke-Command -ComputerName $ComputerName -ScriptBlock {
        param($cmd)
        Invoke-Expression $cmd
    } -ArgumentList $Command
} else {
    # Open interactive remote session
    Enter-PSSession -ComputerName $ComputerName
}