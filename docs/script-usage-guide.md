# Script Usage Guide - helpdesk-ad-automation

Quick reference for the IT support technician using these scripts day-to-day.
All scripts require the ActiveDirectory PowerShell module (RSAT) and must be run
from an account with appropriate AD permissions.

---

## Prerequisites

### Install RSAT on Windows 10/11
```powershell
# Install via PowerShell (Windows 10 1809+ / Windows 11)
Get-WindowsCapability -Name RSAT.ActiveDirectory* -Online |
    Add-WindowsCapability -Online

# Verify installation
Get-Module -Name ActiveDirectory -ListAvailable
```

### Set PowerShell Execution Policy (if scripts are blocked)
```powershell
# Run PowerShell as Administrator
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

---

## Script Reference

### Creating users from a CSV

```powershell
# Prepare your CSV with columns: FirstName,LastName,Department,Title,Manager
# A sample CSV is included at: scripts/ticket-intake/sample_users.csv

# Create users in the Staff OU
.\scripts\active-directory\New-BulkADUsers.ps1 `
    -CsvPath "C:\HR\new_hires.csv" `
    -OUPath "OU=Staff,DC=contoso,DC=local"

# Output: colour-coded log in console + log file in C:\Logs\ADAutomation\
```

### Resetting a password

```powershell
# Interactive — script will prompt for identity verification confirmation
.\scripts\active-directory\Reset-ADUserPassword.ps1 -Username jsmith

# The script will:
# 1. Show full account status
# 2. Prompt you to confirm identity verification
# 3. Unlock the account if locked
# 4. Generate and display a random temporary password
# 5. Log the action (WITHOUT the password — security practice)
```

### Checking and unlocking an account

```powershell
# Check status and unlock if needed
.\scripts\active-directory\Unlock-ADUserAccount.ps1 -Username amina.hassan

# The script handles 4 scenarios:
# - Locked → unlocks + advises on recurring lockout causes
# - Disabled → advises escalation, does NOT re-enable
# - Password expired → directs to Reset-ADUserPassword.ps1
# - Active/fine → guides to investigate non-AD causes
```

### Offboarding a departing employee

```powershell
# Offboard with account move to Disabled Users OU
.\scripts\active-directory\Disable-OffboardedUser.ps1 `
    -Username jsmith `
    -DisabledOU "OU=Disabled Users,DC=contoso,DC=local"

# Offboard in-place (no OU move)
.\scripts\active-directory\Disable-OffboardedUser.ps1 -Username jsmith
```

### Exporting an AD user report

```powershell
# No parameters needed — exports all users to C:\Reports\
.\scripts\active-directory\Export-ADUserReport.ps1

# Output: timestamped CSV with stale account detection and summary statistics
```

### Running the disk monitoring check manually

```powershell
# Run manually to test (normally runs as a Scheduled Task)
.\scripts\disk-monitoring\Watch-DiskSpace.ps1

# To set up as a Scheduled Task:
# Task Scheduler > Create Task
# Trigger: Daily, repeat every 6 hours
# Action: PowerShell.exe -ExecutionPolicy Bypass -File "C:\Scripts\Watch-DiskSpace.ps1"
# Run as: Service account with local admin rights and SMTP relay permission
```

### Remote management

```powershell
# Open interactive remote session to PC001
.\scripts\remote-management\Invoke-RemoteSession.ps1 -ComputerName PC001

# Run a single remote command
.\scripts\remote-management\Invoke-RemoteSession.ps1 `
    -ComputerName PC001 `
    -Command "Get-Service wuauserv | Select-Object Name, Status, StartType"

# Pull last 10 system errors remotely
.\scripts\remote-management\Invoke-RemoteSession.ps1 `
    -ComputerName SERVER01 `
    -Command "Get-EventLog -LogName System -EntryType Error -Newest 10 | Select-Object TimeGenerated, Source, Message"
```

### Running the ticket intake tool

```bash
# Python 3.8+ required
python3 scripts/ticket-intake/ticket_intake.py

# The tool will prompt for:
# - Caller name, department, callback number
# - Affected computer name
# - Issue description
# It will then display categorised triage steps and log to JSON
```

---

## Log Files

All scripts log to `C:\Logs\ADAutomation\`. Log files are:

| Script | Log file |
|--------|---------|
| New-BulkADUsers.ps1 | BulkUserCreate_YYYYMMDD_HHMMSS.log |
| Reset-ADUserPassword.ps1 | PasswordReset_YYYYMMDD.log |
| Unlock-ADUserAccount.ps1 | AccountUnlock_YYYYMMDD.log |
| Disable-OffboardedUser.ps1 | Offboarding_YYYYMMDD.log |
| Export-ADUserReport.ps1 | Reports_YYYYMMDD.log |
| Watch-DiskSpace.ps1 | DiskMonitor_YYYYMM.log |

Ticket intake logs: `helpdesk_tickets_YYYYMM.json` (in working directory)

---

## Common Errors

| Error | Cause | Fix |
|-------|-------|-----|
| "ActiveDirectory module not found" | RSAT not installed | Install RSAT per prerequisites section |
| "Access denied" | Insufficient permissions | Ensure account has required delegation on target OU |
| "OU not found" | Incorrect OUPath format | Copy OUPath from ADUC > object Properties > Attribute Editor > distinguishedName |
| "Cannot connect to WinRM" | WinRM not configured | Run `winrm quickconfig` on target machine as admin |
| "Execution of scripts is disabled" | Execution policy | Run `Set-ExecutionPolicy RemoteSigned -Scope CurrentUser` |
