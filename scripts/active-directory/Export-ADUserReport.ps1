<#**Purpose:** Quarterly access reviews, annual compliance audits, ISO 27001 A.9.2.6
(review of user access rights), and ITIL 4 Change Management documentation all require
accurate, current user reports. Compiling this manually from the AD GUI means clicking
through individual account properties and copying data into a spreadsheet - a process that
takes 2-4 hours for a 100-user directory and produces an error-prone, inconsistently
formatted result. This script produces a comprehensive CSV in under 30 seconds, covering
every field auditors and security teams need: enabled status, last logon date, password
age, stale account detection, and department/role mapping.#>

```powershell
<#
.SYNOPSIS
    Exports all Active Directory users to a structured CSV report for access reviews,
    audits, and compliance documentation.

.DESCRIPTION
    Produces a report covering every AD user account with all fields required for:
      - ITIL 4 Change Management documentation
      - ISO 27001 A.9.2.6 periodic access reviews
      - Security team compliance audits
      - HR offboarding verification (stale/never-logged-in accounts)
      - AD housekeeping (identifies disabled, expired, and dormant accounts)

    Includes a "Days Since Last Logon" calculated column that immediately highlights
    stale accounts (typically defined as 90+ days without logon).

    Time saving: replaces 2–4 hours of manual GUI data collection with a 30-second run.

.EXAMPLE
    .\Export-ADUserReport.ps1

.NOTES
    Output    : C:\Reports\ADUserReport_YYYYMMDD_HHMMSS.csv
    Requires  : ActiveDirectory module (RSAT)
    Run as    : Account with Read access to all user objects in the domain
    Cert align: CompTIA A+, ITIL 4 Change Management
#>

Import-Module ActiveDirectory -ErrorAction Stop

$ReportDir  = "C:\Reports"
$OutputPath = "$ReportDir\ADUserReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
$LogDir     = "C:\Logs\ADAutomation"
$LogFile    = "$LogDir\Reports_$(Get-Date -Format 'yyyyMMdd').log"

foreach ($Dir in @($ReportDir, $LogDir)) {
    if (-not (Test-Path $Dir)) { New-Item -ItemType Directory -Path $Dir -Force | Out-Null }
}

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $Entry = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level] $Message"
    Add-Content -Path $LogFile -Value $Entry
    Write-Host $Entry
}

Write-Log "AD User Report started by $($env:USERNAME) on $($env:COMPUTERNAME)"
Write-Host "Collecting all AD user accounts — this may take a moment for large directories..." -ForegroundColor Cyan

$Now = Get-Date

$Users = Get-ADUser -Filter * -Properties `
    DisplayName, SamAccountName, UserPrincipalName, EmailAddress,
    Department, Title, Manager, Enabled, LockedOut,
    LastLogonDate, PasswordLastSet, PasswordNeverExpires,
    PasswordExpired, PasswordNotRequired, Created, Modified,
    Description, DistinguishedName |
    Select-Object `
        @{N="Full Name";              E={ $_.DisplayName }},
        @{N="Username";               E={ $_.SamAccountName }},
        @{N="UPN (Email Login)";      E={ $_.UserPrincipalName }},
        @{N="Email Address";          E={ $_.EmailAddress }},
        @{N="Department";             E={ $_.Department }},
        @{N="Job Title";              E={ $_.Title }},
        @{N="Manager";                E={ if ($_.Manager) { try { (Get-ADUser $_.Manager -ErrorAction Stop).DisplayName } catch { $_.Manager } } else { "None" } }},
        @{N="Account Enabled";        E={ $_.Enabled }},
        @{N="Account Locked";         E={ $_.LockedOut }},
        @{N="Password Expired";       E={ $_.PasswordExpired }},
        @{N="PW Never Expires";       E={ $_.PasswordNeverExpires }},
        @{N="PW Not Required";        E={ $_.PasswordNotRequired }},
        @{N="Last Logon Date";        E={ $_.LastLogonDate }},
        @{N="Days Since Last Logon";  E={ if ($_.LastLogonDate) { [math]::Round(($Now - $_.LastLogonDate).TotalDays, 0) } else { "Never logged in" } }},
        @{N="Stale (90+ days)";       E={ if ($_.LastLogonDate) { ($Now - $_.LastLogonDate).TotalDays -gt 90 } else { $true } }},
        @{N="Password Last Set";      E={ $_.PasswordLastSet }},
        @{N="Account Created";        E={ $_.Created }},
        @{N="Account Last Modified";  E={ $_.Modified }},
        @{N="Description";            E={ $_.Description }},
        @{N="OU / Distinguished Name";E={ ($_.DistinguishedName -replace '^CN=[^,]+,', '') }}

$Users | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8

# ─────────────────────────────────────────────────────────────
#  SUMMARY STATISTICS TO CONSOLE AND LOG
# ─────────────────────────────────────────────────────────────
$Total        = $Users.Count
$Enabled      = ($Users | Where-Object { $_."Account Enabled" -eq $true }).Count
$Disabled     = ($Users | Where-Object { $_."Account Enabled" -eq $false }).Count
$Locked       = ($Users | Where-Object { $_."Account Locked" -eq $true }).Count
$PWExpired    = ($Users | Where-Object { $_."Password Expired" -eq $true }).Count
$PWNeverExp   = ($Users | Where-Object { $_."PW Never Expires" -eq $true }).Count
$Stale        = ($Users | Where-Object { $_."Stale (90+ days)" -eq $true }).Count
$NeverLoggedIn = ($Users | Where-Object { $_."Days Since Last Logon" -eq "Never logged in" }).Count

Write-Host ""
Write-Host "══════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "  AD USER REPORT — COMPLETE" -ForegroundColor Green
Write-Host "══════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "  Total accounts          : $Total"
Write-Host "  Enabled                 : $Enabled"
Write-Host "  Disabled                : $Disabled"
Write-Host "  Currently locked        : $Locked"
Write-Host "  Password expired        : $PWExpired"
Write-Host "  PW never expires (risk) : $PWNeverExp  ← review these accounts"
Write-Host "  Stale (90+ days)        : $Stale  ← flag for access review"
Write-Host "  Never logged in         : $NeverLoggedIn  ← investigate or disable"
Write-Host "══════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "  Report saved : $OutputPath" -ForegroundColor Cyan
Write-Host ""

Write-Log "Report complete. Total: $Total | Enabled: $Enabled | Disabled: $Disabled | Stale: $Stale | Never logged in: $NeverLoggedIn"
Write-Log "Report saved to: $OutputPath"
