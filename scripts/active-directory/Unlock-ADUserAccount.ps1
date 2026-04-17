<#
 **Purpose:** Account lockout is one of the five most common help desk tickets. The wrong
approach is to blindly unlock without checking context - an account that is disabled (not
locked) will look the same to a user who says "I can't log in." This script checks the
full account status and tells the technician exactly what is happening and exactly what to
do - it handles four distinct scenarios: locked (unlock), disabled (escalate, do not
re-enable), password expired (direct to password reset script), or active with no issue
(investigate other causes). It prevents the common mistake of re-enabling an intentionally
disabled offboarded employee's account.
#>

```powershell
<#
.SYNOPSIS
    Checks Active Directory account status and unlocks a locked-out account.

.DESCRIPTION
    Intelligently handles four scenarios that all present to users as "I can't log in":
      1. Account is locked out   → unlocks and advises on recurring lockout causes
      2. Account is disabled     → advises escalation; does NOT re-enable
      3. Password is expired     → directs to password reset; does NOT unlock
      4. Account is active/fine  → guides technician to investigate non-AD causes

    Displays comprehensive account health information before taking any action.
    All actions are logged with timestamps and operator identity.

    Why this matters: Blindly unlocking without context risks re-enabling a disabled
    account that was deactivated for a reason (offboarding, security suspension, HR action).

.PARAMETER Username
    The SamAccountName of the account to check/unlock.

.EXAMPLE
    .\Unlock-ADUserAccount.ps1 -Username jsmith
    .\Unlock-ADUserAccount.ps1 -Username brian.otieno

.NOTES
    Requires  : ActiveDirectory PowerShell module (RSAT)
    Run as    : Account with Read + Unlock Account rights on target OU
    Cert align: CompTIA A+, ITIL 4 Incident Management
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$Username
)

Import-Module ActiveDirectory -ErrorAction Stop

# ─────────────────────────────────────────────────────────────
#  LOGGING
# ─────────────────────────────────────────────────────────────
$LogDir  = "C:\Logs\ADAutomation"
$LogFile = "$LogDir\AccountUnlock_$(Get-Date -Format 'yyyyMMdd').log"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
    $Entry = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level] [Op: $env:USERNAME] $Message"
    Add-Content -Path $LogFile -Value $Entry
}

# ─────────────────────────────────────────────────────────────
#  RETRIEVE ACCOUNT
# ─────────────────────────────────────────────────────────────
$User = Get-ADUser -Filter { SamAccountName -eq $Username } `
        -Properties DisplayName, Department, Enabled, LockedOut,
                    BadLogonCount, LastBadPasswordAttempt,
                    LastLogonDate, PasswordExpired, PasswordLastSet,
                    PasswordNeverExpires `
        -ErrorAction SilentlyContinue

if (-not $User) {
    Write-Host "`n[ERROR] Account '$Username' not found in Active Directory." -ForegroundColor Red
    Write-Host "Verify the SamAccountName. It is the Windows login name, not the display name." -ForegroundColor Yellow
    Write-Log "ERROR: Account '$Username' not found." "ERROR"
    exit 1
}

Write-Log "Account status check for '$Username' by operator $env:USERNAME"

# ─────────────────────────────────────────────────────────────
#  DISPLAY FULL STATUS
# ─────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "══════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  ACCOUNT DIAGNOSTIC REPORT" -ForegroundColor Cyan
Write-Host "══════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Display Name      : $($User.DisplayName)"
Write-Host "  SamAccountName    : $($User.SamAccountName)"
Write-Host "  Department        : $($User.Department)"
Write-Host "──────────────────────────────────────────────────" -ForegroundColor DarkCyan
Write-Host "  Account Enabled   : $($User.Enabled)"
Write-Host "  Locked Out        : $($User.LockedOut)"
Write-Host "  Password Expired  : $($User.PasswordExpired)"
Write-Host "  PW Never Expires  : $($User.PasswordNeverExpires)"
Write-Host "  Bad Logon Count   : $($User.BadLogonCount)"
Write-Host "  Last Bad Attempt  : $($User.LastBadPasswordAttempt)"
Write-Host "  Password Set On   : $($User.PasswordLastSet)"
Write-Host "  Last Successful   : $($User.LastLogonDate)"
Write-Host "══════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# ─────────────────────────────────────────────────────────────
#  SCENARIO ROUTING
# ─────────────────────────────────────────────────────────────

# SCENARIO 1: Account is locked out — this is the primary L1 action
if ($User.LockedOut) {
    try {
        Unlock-ADAccount -Identity $Username
        Write-Log "Account '$Username' ($($User.DisplayName)) unlocked by $env:USERNAME." "SUCCESS"

        Write-Host "  ✔ ACTION TAKEN: Account unlocked successfully." -ForegroundColor Green
        Write-Host ""
        Write-Host "  NEXT STEPS FOR THE TECHNICIAN:" -ForegroundColor Cyan
        Write-Host "  1. Ask the user to attempt login now."
        Write-Host "  2. Confirm login succeeds before closing the ticket."
        Write-Host ""
        Write-Host "  IF LOCKOUTS KEEP RECURRING — advise the user to check:" -ForegroundColor Yellow
        Write-Host "  - Saved credentials on mobile phone (old password cached)"
        Write-Host "  - Windows Credential Manager: Control Panel > Credential Manager"
        Write-Host "  - Mapped network drives using the old password"
        Write-Host "  - Outlook or email clients with saved old password"
        Write-Host "  - Scheduled tasks or services running under this account"
        Write-Host ""
        Write-Host "  If lockouts recur after this unlock: RAISE A PROBLEM TICKET." -ForegroundColor Yellow
        Write-Host "  Recurring lockouts indicate a root cause that L1 unlock does not fix." -ForegroundColor Yellow

    } catch {
        Write-Log "ERROR: Unlock failed for '$Username'. Error: $($_.Exception.Message)" "ERROR"
        Write-Host "  ✘ Unlock FAILED. Error: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "  Check your account has 'Unlock Account' delegation on this OU." -ForegroundColor Yellow
    }

# SCENARIO 2: Account is disabled — NOT a lockout — escalation required
} elseif (-not $User.Enabled) {
    Write-Log "Account '$Username' is DISABLED — operator advised to escalate." "WARN"

    Write-Host "  ⚠  ACCOUNT IS DISABLED" -ForegroundColor Red
    Write-Host ""
    Write-Host "  This account has been DISABLED, not locked." -ForegroundColor Red
    Write-Host "  These are different states with different procedures." -ForegroundColor Red
    Write-Host ""
    Write-Host "  DO NOT re-enable this account at L1." -ForegroundColor Red
    Write-Host ""
    Write-Host "  Accounts are disabled for intentional reasons:" -ForegroundColor Yellow
    Write-Host "  - Employee offboarding or termination" -ForegroundColor Yellow
    Write-Host "  - Security suspension (suspected compromise)" -ForegroundColor Yellow
    Write-Host "  - HR or compliance hold" -ForegroundColor Yellow
    Write-Host "  - Long-term leave with account suspended per policy" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  ESCALATE TO L2 with:" -ForegroundColor Cyan
    Write-Host "  - Username: $Username" -ForegroundColor Cyan
    Write-Host "  - Caller name, department, and contact" -ForegroundColor Cyan
    Write-Host "  - Business justification for re-enablement" -ForegroundColor Cyan
    Write-Host "  - Manager name and confirmation if possible" -ForegroundColor Cyan

# SCENARIO 3: Password is expired — password reset is needed, not account unlock
} elseif ($User.PasswordExpired) {
    Write-Log "Account '$Username' has an EXPIRED password — redirected to password reset." "INFO"

    Write-Host "  ⚠  PASSWORD IS EXPIRED (account is not locked)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  The account is active and not locked — the password has simply expired." -ForegroundColor Yellow
    Write-Host "  Unlocking this account will have no effect." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  CORRECT ACTION: Run the password reset script:" -ForegroundColor Cyan
    Write-Host "  .\Reset-ADUserPassword.ps1 -Username $Username" -ForegroundColor Green

# SCENARIO 4: Account is active with no apparent issue
} else {
    Write-Log "Account '$Username' is active, not locked, not disabled, password not expired. No AD-side action taken." "INFO"

    Write-Host "  ✔ Account is ACTIVE — not locked, not disabled, password not expired." -ForegroundColor Green
    Write-Host ""
    Write-Host "  The issue is NOT in Active Directory." -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  INVESTIGATE THESE COMMON NON-AD CAUSES:" -ForegroundColor Yellow
    Write-Host "  - User selecting wrong domain at login (check domain field)"
    Write-Host "  - Caps Lock or Num Lock active"
    Write-Host "  - User typing password into the username field"
    Write-Host "  - Cached/stale credentials on a different machine"
    Write-Host "  - Roaming profile corruption"
    Write-Host "  - Machine trust account issue (computer account in AD may need reset)"
    Write-Host ""
    Write-Host "  TEST: Ask user to try logging in at a DIFFERENT computer." -ForegroundColor Cyan
    Write-Host "  If it works on another machine: local machine profile issue." -ForegroundColor Cyan
}

Write-Host ""
Write-Host "  Log file: $LogFile" -ForegroundColor DarkGray
Write-Host ""
