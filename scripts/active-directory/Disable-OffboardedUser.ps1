**Purpose:** Employee offboarding is a critical IT security process. When an employee leaves - voluntarily or otherwise - their access must be revoked immediately and completely.
Missed offboarding is a serious security risk: terminated employees with active accounts
can exfiltrate data, access confidential systems, or cause damage. This script performs
the complete offboarding checklist: disables the account, resets the password to an
unguessable random string (preventing re-entry even if the old password is known), moves
the account to a disabled OU for audit purposes, and logs every action with timestamps
and the name of the IT operator who performed the offboarding.

```powershell
<#
.SYNOPSIS
    Performs a complete Active Directory offboarding for a departing employee.

.DESCRIPTION
    Executes the full IT offboarding checklist for an AD user account:
      1. Verifies account exists and is currently enabled
      2. Disables the account (blocks all logon immediately)
      3. Resets the password to an unguessable random string
         (prevents re-entry even if the old password was memorised)
      4. Clears the account description and sets it to "OFFBOARDED - [Date]"
      5. Moves the account to a designated "Disabled Users" OU
         (keeps the account for the retention period before deletion)
      6. Logs all actions with timestamp and operator identity

    ITIL 4 alignment: This is a Change Management action. The log entry this script
    produces should be attached to the offboarding change ticket.

    SECURITY NOTE: This script does NOT delete the account. Accounts should be
    retained for a configurable period (typically 30–90 days) before deletion to
    allow for data recovery, email forwarding, and audit purposes.

.PARAMETER Username
    SamAccountName of the account to offboard.

.PARAMETER DisabledOU
    Distinguished Name of the OU where disabled accounts should be moved.
    Example: "OU=Disabled Users,DC=contoso,DC=local"
    If not specified, account is disabled in place without moving.

.EXAMPLE
    .\Disable-OffboardedUser.ps1 -Username jsmith -DisabledOU "OU=Disabled Users,DC=contoso,DC=local"

.EXAMPLE
    .\Disable-OffboardedUser.ps1 -Username amina.hassan

.NOTES
    Requires  : ActiveDirectory module (RSAT)
    Run as    : Domain Admin or delegated account with Disable, Reset Password, Move Object rights
    Cert align: CompTIA A+, Security+, ITIL 4 Change Management
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$Username,

    [Parameter(Mandatory = $false)]
    [string]$DisabledOU = ""
)

# ─────────────────────────────────────────────────────────────
#  LOGGING
# ─────────────────────────────────────────────────────────────
$LogDir  = "C:\Logs\ADAutomation"
$LogFile = "$LogDir\Offboarding_$(Get-Date -Format 'yyyyMMdd').log"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
    $Entry = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level] [Op: $env:USERNAME] $Message"
    Add-Content -Path $LogFile -Value $Entry
    $Colour = switch ($Level) {
        "SUCCESS" { "Green" } "WARN" { "Yellow" } "ERROR" { "Red" } default { "Cyan" }
    }
    Write-Host $Entry -ForegroundColor $Colour
}

# ─────────────────────────────────────────────────────────────
#  RANDOM PASSWORD (for post-disable reset)
# ─────────────────────────────────────────────────────────────
function New-RandomPassword {
    $Chars = 'ABCDEFGHJKMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789!@#$%&*'
    return -join ((1..24) | ForEach-Object { $Chars[(Get-Random -Maximum $Chars.Length)] })
}

Import-Module ActiveDirectory -ErrorAction Stop

# ─────────────────────────────────────────────────────────────
#  RETRIEVE AND VALIDATE
# ─────────────────────────────────────────────────────────────
Write-Log "Offboarding initiated for: $Username"

$User = Get-ADUser -Filter { SamAccountName -eq $Username } `
        -Properties DisplayName, Department, Title, Enabled, DistinguishedName `
        -ErrorAction SilentlyContinue

if (-not $User) {
    Write-Log "ERROR: Account '$Username' not found." "ERROR"
    Write-Host "`nAccount '$Username' not found. Verify the username." -ForegroundColor Red
    exit 1
}

if (-not $User.Enabled) {
    Write-Log "WARN: Account '$Username' is already disabled. Proceeding with remaining steps." "WARN"
    Write-Host "NOTE: Account is already disabled. Continuing with password reset and move." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "══════════════════════════════════════════════════" -ForegroundColor Yellow
Write-Host "  OFFBOARDING: $($User.DisplayName) ($Username)" -ForegroundColor Yellow
Write-Host "  Department: $($User.Department) | Title: $($User.Title)" -ForegroundColor Yellow
Write-Host "══════════════════════════════════════════════════" -ForegroundColor Yellow
Write-Host ""

$Confirm = Read-Host "Confirm offboarding for '$($User.DisplayName)' ($Username)? Type OFFBOARD to proceed"
if ($Confirm -ne "OFFBOARD") {
    Write-Log "Offboarding CANCELLED by operator for '$Username'." "WARN"
    Write-Host "Offboarding cancelled." -ForegroundColor Yellow
    exit 0
}

$OffboardDate = Get-Date -Format "yyyy-MM-dd"
$Errors = 0

# ── Step 1: Disable the account ──────────────────────────────
try {
    Disable-ADAccount -Identity $Username
    Write-Log "STEP 1 SUCCESS: Account '$Username' disabled." "SUCCESS"
} catch {
    Write-Log "STEP 1 ERROR: Failed to disable '$Username'. $($_.Exception.Message)" "ERROR"
    $Errors++
}

# ── Step 2: Reset password to unguessable random string ──────
try {
    $RandomPW = New-RandomPassword
    Set-ADAccountPassword -Identity $Username -NewPassword (ConvertTo-SecureString $RandomPW -AsPlainText -Force) -Reset
    Write-Log "STEP 2 SUCCESS: Password reset to random value for '$Username'. (Value not logged)" "SUCCESS"
    $RandomPW = $null  # Clear from memory
} catch {
    Write-Log "STEP 2 ERROR: Failed to reset password for '$Username'. $($_.Exception.Message)" "ERROR"
    $Errors++
}

# ── Step 3: Update description ────────────────────────────────
try {
    Set-ADUser -Identity $Username -Description "OFFBOARDED: $OffboardDate | By: $env:USERNAME"
    Write-Log "STEP 3 SUCCESS: Description updated to reflect offboarding date." "SUCCESS"
} catch {
    Write-Log "STEP 3 WARN: Could not update description. $($_.Exception.Message)" "WARN"
}

# ── Step 4: Move to disabled OU (if specified and valid) ──────
if ($DisabledOU -ne "") {
    try {
        $DisabledOUCheck = Get-ADOrganizationalUnit -Filter { DistinguishedName -eq $DisabledOU } -ErrorAction Stop
        if ($DisabledOUCheck) {
            Move-ADObject -Identity $User.DistinguishedName -TargetPath $DisabledOU
            Write-Log "STEP 4 SUCCESS: Account moved to disabled OU: $DisabledOU" "SUCCESS"
        }
    } catch {
        Write-Log "STEP 4 WARN: Could not move account to disabled OU. $($_.Exception.Message)" "WARN"
    }
} else {
    Write-Log "STEP 4 SKIP: No DisabledOU specified — account left in original OU." "INFO"
}

# ── Summary ───────────────────────────────────────────────────
Write-Host ""
if ($Errors -eq 0) {
    Write-Host "  ✔ OFFBOARDING COMPLETE — all steps succeeded." -ForegroundColor Green
} else {
    Write-Host "  ⚠  OFFBOARDING PARTIAL — $Errors step(s) encountered errors. Review log." -ForegroundColor Yellow
}
Write-Host "  User    : $($User.DisplayName) ($Username)"
Write-Host "  Date    : $OffboardDate"
Write-Host "  By      : $($env:USERNAME)"
Write-Host "  Log     : $LogFile"
Write-Host ""
Write-Host "  REMAINING OFFBOARDING TASKS (outside this script's scope):" -ForegroundColor Cyan
Write-Host "  - Revoke Microsoft 365 sessions and licences"
Write-Host "  - Remove from all distribution groups and shared mailboxes"
Write-Host "  - Disable multi-factor authentication methods"
Write-Host "  - Recover company devices"
Write-Host "  - Transfer email to manager (per policy)"
Write-Host "  - Retain account for 30–90 days before deletion (per retention policy)"
Write-Host ""
Write-Log "Offboarding complete for '$Username'. Errors: $Errors"
