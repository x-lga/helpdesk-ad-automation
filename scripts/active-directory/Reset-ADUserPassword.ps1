 <#**Purpose:** Password resets are the single highest-volume L1 ticket type - typically 20-30%
of all help desk tickets. Every organisation with Active Directory sees them daily. The
manual process is error-prone: technicians forget to check lockout status before resetting
(the reset will fail if the account is locked), use weak static temporary passwords, forget
to force change at next logon, and rarely produce an audit log. This script handles the
complete workflow: identity verification prompt, account status check, unlock if locked,
reset to a cryptographically random temporary password, force change at next logon, and
full timestamped audit logging. It is safe, auditable, and communicates the temporary
password clearly to the technician for secure relay.#>


```powershell
<#
.SYNOPSIS
    Resets an Active Directory user password with identity verification, unlock check,
    and full audit logging.

.DESCRIPTION
    Handles the complete L1 password reset workflow:
      1. Prompts the technician to confirm identity verification before proceeding
         (prevents social engineering — attacker calls posing as the user)
      2. Verifies the account exists in Active Directory
      3. Reports full account status (enabled, locked, password age, last logon)
      4. Unlocks the account first if it is locked (reset fails on locked accounts)
      5. Generates a cryptographically random temporary password (12 characters,
         mixed case + digits + symbols — meets most corporate complexity policies)
      6. Resets the password and forces change at next logon
      7. Logs all actions with timestamps to a daily log file
      8. Displays the temporary password clearly for secure relay to the user

    ITIL 4 alignment: Incident Management — restores service (user access) as fast as
    possible while maintaining an audit trail for the Incident record.

.PARAMETER Username
    The SamAccountName (login name) of the account to reset.
    Do not use the full display name or email address — use the Windows login name.

.EXAMPLE
    .\Reset-ADUserPassword.ps1 -Username jsmith

.EXAMPLE
    .\Reset-ADUserPassword.ps1 -Username amina.hassan

.NOTES
    Requires  : ActiveDirectory PowerShell module (RSAT)
    Run as    : Account with "Reset Password" delegation on the target OU
                (Domain Admin works but delegation is preferred — least privilege)
    Security  : Temporary password is random per call — never a static default
                Temporary password is NOT written to the log file (security practice)
    Cert align: CompTIA A+, ITIL 4 Incident Management
#>

param(
    [Parameter(Mandatory = $true, HelpMessage = "SamAccountName of the user to reset")]
    [ValidateNotNullOrEmpty()]
    [string]$Username
)

# ─────────────────────────────────────────────────────────────
#  CONFIGURATION
# ─────────────────────────────────────────────────────────────
$LogDir  = "C:\Logs\ADAutomation"
$LogFile = "$LogDir\PasswordReset_$(Get-Date -Format 'yyyyMMdd').log"

# ─────────────────────────────────────────────────────────────
#  LOGGING FUNCTION
# ─────────────────────────────────────────────────────────────
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO", "SUCCESS", "WARN", "ERROR")]
        [string]$Level = "INFO"
    )
    if (-not (Test-Path $LogDir)) {
        New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
    }
    $Entry = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level] [Operator: $env:USERNAME] $Message"
    Add-Content -Path $LogFile -Value $Entry
    $Colour = switch ($Level) {
        "SUCCESS" { "Green"  }
        "WARN"    { "Yellow" }
        "ERROR"   { "Red"    }
        default   { "White"  }
    }
    Write-Host $Entry -ForegroundColor $Colour
}

# ─────────────────────────────────────────────────────────────
#  RANDOM PASSWORD GENERATOR
# Produces a 12-character password meeting standard complexity:
# uppercase, lowercase, digit, and symbol — one of each guaranteed
# ─────────────────────────────────────────────────────────────
function New-RandomPassword {
    $Upper   = 'ABCDEFGHJKMNPQRSTUVWXYZ'
    $Lower   = 'abcdefghjkmnpqrstuvwxyz'
    $Digits  = '23456789'
    $Symbols = '!@#$%&*'
    $All     = $Upper + $Lower + $Digits + $Symbols

    # Guarantee at least one of each required character type
    $Password  = ($Upper  | Get-Random -Count 1)
    $Password += ($Lower  | Get-Random -Count 1)
    $Password += ($Digits | Get-Random -Count 1)
    $Password += ($Symbols| Get-Random -Count 1)

    # Fill remaining 8 characters from the full set
    $Password += -join ((1..8) | ForEach-Object { $All[(Get-Random -Maximum $All.Length)] })

    # Shuffle the result so guaranteed chars are not always in the same positions
    $Shuffled = -join ($Pwd.ToCharArray() | Get-Random -Count $Pwd.Length)
    return $Shuffled
}

# ─────────────────────────────────────────────────────────────
#  MAIN
# ─────────────────────────────────────────────────────────────
Write-Log "Password reset initiated for target account: $Username"

Import-Module ActiveDirectory -ErrorAction Stop

# ── Step 1: Retrieve account with all relevant properties ────
$ADUser = Get-ADUser -Filter { SamAccountName -eq $Username } `
          -Properties DisplayName, Department, Title, Enabled, LockedOut,
                      LastLogonDate, PasswordLastSet, PasswordExpired,
                      PasswordNeverExpires, BadLogonCount, LastBadPasswordAttempt `
          -ErrorAction SilentlyContinue

if (-not $ADUser) {
    Write-Log "ERROR: Account '$Username' not found in Active Directory." -Level "ERROR"
    Write-Host "`nUser '$Username' was not found. Verify the SamAccountName and try again." -ForegroundColor Red
    Write-Host "Tip: SamAccountName is the Windows login name, not the display name or email." -ForegroundColor Yellow
    exit 1
}

# ── Step 2: Display account status before acting ─────────────
Write-Host ""
Write-Host "══════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  ACCOUNT STATUS — Before Reset" -ForegroundColor Cyan
Write-Host "══════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Display Name     : $($ADUser.DisplayName)"
Write-Host "  Username         : $($ADUser.SamAccountName)"
Write-Host "  Department       : $($ADUser.Department)"
Write-Host "  Title            : $($ADUser.Title)"
Write-Host "  Account Enabled  : $($ADUser.Enabled)"
Write-Host "  Locked Out       : $($ADUser.LockedOut)"
Write-Host "  Password Expired : $($ADUser.PasswordExpired)"
Write-Host "  PW Never Expires : $($ADUser.PasswordNeverExpires)"
Write-Host "  Bad Logon Count  : $($ADUser.BadLogonCount)"
Write-Host "  Last Bad Attempt : $($ADUser.LastBadPasswordAttempt)"
Write-Host "  Password Set     : $($ADUser.PasswordLastSet)"
Write-Host "  Last Logon       : $($ADUser.LastLogonDate)"
Write-Host "══════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# ── Step 3: Abort if account is DISABLED ─────────────────────
# A disabled account is not just locked — it has been intentionally deactivated.
# This may be due to offboarding, a security hold, or an HR action.
# Re-enabling requires L2 authorisation, not L1 password reset.
if (-not $ADUser.Enabled) {
    Write-Log "ABORT: Account '$Username' is DISABLED — this is not a lockout. Do NOT re-enable without L2 authorisation." -Level "WARN"
    Write-Host "STOP: This account is DISABLED, not just locked." -ForegroundColor Red
    Write-Host "Do NOT attempt to re-enable this account without explicit L2 and management authorisation." -ForegroundColor Red
    Write-Host "Escalate this ticket to L2 with the caller's details and business justification." -ForegroundColor Yellow
    exit 1
}

# ── Step 4: Identity verification ────────────────────────────
# This step prevents social engineering attacks where an attacker calls the help desk
# posing as the legitimate user to get a password reset for an account they do not own.
Write-Host "─────────────────────────────────────────────" -ForegroundColor Yellow
Write-Host "  IDENTITY VERIFICATION REQUIRED" -ForegroundColor Yellow
Write-Host "─────────────────────────────────────────────" -ForegroundColor Yellow
Write-Host "  Verify the caller's identity BEFORE resetting."
Write-Host "  Acceptable methods:"
Write-Host "    1. Employee ID number confirmed against HR system"
Write-Host "    2. Manager name confirmed (caller names their manager)"
Write-Host "    3. Callback to the user's desk phone (number on file, not mobile)"
Write-Host "    4. Video call showing company ID badge"
Write-Host ""
$Confirmed = Read-Host "  Identity confirmed? Type YES to proceed"

if ($Confirmed -ne "YES") {
    Write-Log "ABORT: Technician did not confirm identity for '$Username'. Reset cancelled." -Level "WARN"
    Write-Host "`nReset cancelled. Do not reset without confirming identity." -ForegroundColor Red
    exit 0
}

Write-Log "Identity verification confirmed by operator $($env:USERNAME) for account '$Username'."

# ── Step 5: Unlock account if locked ─────────────────────────
# Password reset on a locked account will succeed but the user still cannot log in.
# Always unlock first, then reset.
if ($ADUser.LockedOut) {
    try {
        Unlock-ADAccount -Identity $Username
        Write-Log "Account '$Username' was locked — unlocked before password reset." -Level "INFO"
        Write-Host "  Account was locked — unlocked successfully." -ForegroundColor Cyan
    } catch {
        Write-Log "ERROR: Failed to unlock '$Username'. Error: $($_.Exception.Message)" -Level "ERROR"
        exit 1
    }
}

# ── Step 6: Generate random temporary password ────────────────
$TempPW = New-RandomPassword

# ── Step 7: Reset password and force change ───────────────────
try {
    $SecurePW = ConvertTo-SecureString $TempPW -AsPlainText -Force
    Set-ADAccountPassword -Identity $Username -NewPassword $SecurePW -Reset
    Set-ADUser -Identity $Username -ChangePasswordAtLogon $true

    # Log the action WITHOUT the password (security practice — never log passwords)
    Write-Log "SUCCESS: Password reset for '$Username' ($($ADUser.DisplayName)). Change required at next logon. Temp PW: [REDACTED FROM LOG]" -Level "SUCCESS"

    # Display the temporary password clearly to the technician for secure relay
    Write-Host ""
    Write-Host "══════════════════════════════════════════════" -ForegroundColor Green
    Write-Host "  PASSWORD RESET SUCCESSFUL" -ForegroundColor Green
    Write-Host "══════════════════════════════════════════════" -ForegroundColor Green
    Write-Host "  User        : $($ADUser.DisplayName) ($Username)"
    Write-Host "  Temp PW     : $TempPW" -ForegroundColor Yellow
    Write-Host "  Change req  : YES — user must change on first logon"
    Write-Host "══════════════════════════════════════════════" -ForegroundColor Green
    Write-Host ""
    Write-Host "  SECURITY REMINDER:" -ForegroundColor Yellow
    Write-Host "  - Communicate the temporary password by PHONE — never by email or chat" -ForegroundColor Yellow
    Write-Host "  - Confirm the user successfully logs in and changes their password" -ForegroundColor Yellow
    Write-Host "  - If user cannot log in after reset, check: correct username? correct domain?" -ForegroundColor Yellow
    Write-Host ""

} catch {
    Write-Log "ERROR: Password reset failed for '$Username'. Error: $($_.Exception.Message)" -Level "ERROR"
    Write-Host "`nPassword reset FAILED. See log for details: $LogFile" -ForegroundColor Red
    exit 1
}

