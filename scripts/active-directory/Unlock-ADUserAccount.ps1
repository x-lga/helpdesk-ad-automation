<#
.SYNOPSIS
    Unlocks a locked-out Active Directory account.

.DESCRIPTION
    Checks lockout status, unlocks if needed, and logs the action.
    Common L1 ticket: "User cannot log in" — account lockout is the most frequent cause.

.PARAMETER Username
    The SamAccountName of the locked user.

.EXAMPLE
    .\Unlock-ADUserAccount.ps1 -Username jsmith
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$Username
)

Import-Module ActiveDirectory -ErrorAction Stop

$User = Get-ADUser -Filter {SamAccountName -eq $Username} `
        -Properties LockedOut, BadLogonCount, LastBadPasswordAttempt, Enabled

if (-not $User) {
    Write-Host "ERROR: User '$Username' not found." -ForegroundColor Red
    exit 1
}

Write-Host "`n--- Account Status for: $($User.DisplayName) ---"
Write-Host "Enabled         : $($User.Enabled)"
Write-Host "Locked Out      : $($User.LockedOut)"
Write-Host "Bad Logon Count : $($User.BadLogonCount)"
Write-Host "Last Bad Attempt: $($User.LastBadPasswordAttempt)"

if ($User.LockedOut) {
    Unlock-ADAccount -Identity $Username
    Write-Host "`nSUCCESS: Account unlocked for $Username." -ForegroundColor Green
    Write-Host "Advise user: If lockouts continue, check for saved credentials on old devices or mapped drives."
} elseif (-not $User.Enabled) {
    Write-Host "`nWARN: Account is DISABLED — not locked. Escalate to L2 for re-enable authorisation." -ForegroundColor Yellow
} else {
    Write-Host "`nINFO: Account is not locked. Investigate other causes (wrong domain, Caps Lock, etc.)." -ForegroundColor Cyan
}