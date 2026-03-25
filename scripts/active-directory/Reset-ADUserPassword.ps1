<#
.SYNOPSIS
    Resets an AD user password and forces change at next logon.

.DESCRIPTION
    L1 help desk password reset script.
    Verifies the account exists before attempting reset.
    Logs all actions with timestamp.

.PARAMETER Username
    The SamAccountName of the user to reset.

.EXAMPLE
    .\Reset-ADUserPassword.ps1 -Username jsmith

.NOTES
    Requires: ActiveDirectory module (RSAT)
    Run as: Account with 'Reset Password' delegation on target OU
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$Username
)

$LogFile   = "C:\Logs\PasswordReset_$(Get-Date -Format 'yyyyMMdd').log"
$TempPW    = "TempReset@$(Get-Random -Minimum 1000 -Maximum 9999)!"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $Entry = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level] $Message"
    Add-Content -Path $LogFile -Value $Entry
    Write-Host $Entry
}

if (-not (Test-Path "C:\Logs")) { New-Item -ItemType Directory -Path "C:\Logs" | Out-Null }

Import-Module ActiveDirectory -ErrorAction Stop

# --- Verify account exists ---
$ADUser = Get-ADUser -Filter {SamAccountName -eq $Username} -Properties LockedOut, Enabled, LastLogonDate

if (-not $ADUser) {
    Write-Log "ERROR: User '$Username' not found in Active Directory." -Level "ERROR"
    exit 1
}

Write-Log "Found user: $($ADUser.DisplayName) | Enabled: $($ADUser.Enabled) | Locked: $($ADUser.LockedOut)"

# --- Check if account is locked (unlock before reset) ---
if ($ADUser.LockedOut) {
    Unlock-ADAccount -Identity $Username
    Write-Log "Unlocked locked account for $Username before password reset."
}

# --- Reset password ---
try {
    Set-ADAccountPassword -Identity $Username `
        -NewPassword (ConvertTo-SecureString $TempPW -AsPlainText -Force) `
        -Reset

    Set-ADUser -Identity $Username -ChangePasswordAtLogon $true

    Write-Log "SUCCESS: Password reset for $Username. Temp PW: $TempPW (communicate securely to user)"
    Write-Host "`n>>> Temporary password: $TempPW <<<`n" -ForegroundColor Green
    Write-Host "Communicate this to the user via a secure channel (NOT email)."

} catch {
    Write-Log "ERROR: Reset failed for $Username — $($_.Exception.Message)" -Level "ERROR"
}