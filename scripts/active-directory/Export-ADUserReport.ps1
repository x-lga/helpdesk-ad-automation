<#
.SYNOPSIS
    Exports all AD users to a CSV with key fields for auditing.

.DESCRIPTION
    Produces a report of all users including enabled status, last logon,
    department, and password expiry. Used for access reviews and ITIL 4
    Change Management documentation.

.EXAMPLE
    .\Export-ADUserReport.ps1
#>

Import-Module ActiveDirectory -ErrorAction Stop

$OutputPath = "C:\Reports\ADUserReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"

if (-not (Test-Path "C:\Reports")) { New-Item -ItemType Directory -Path "C:\Reports" | Out-Null }

$Users = Get-ADUser -Filter * -Properties `
    DisplayName, SamAccountName, UserPrincipalName, Department, Title,
    Enabled, LockedOut, LastLogonDate, PasswordLastSet, PasswordNeverExpires,
    Created, Manager |
    Select-Object `
        @{N="Full Name";      E={$_.DisplayName}},
        @{N="Username";       E={$_.SamAccountName}},
        @{N="UPN";            E={$_.UserPrincipalName}},
        @{N="Department";     E={$_.Department}},
        @{N="Title";          E={$_.Title}},
        @{N="Enabled";        E={$_.Enabled}},
        @{N="Locked";         E={$_.LockedOut}},
        @{N="Last Logon";     E={$_.LastLogonDate}},
        @{N="Password Set";   E={$_.PasswordLastSet}},
        @{N="PW Never Exp";   E={$_.PasswordNeverExpires}},
        @{N="Account Created";E={$_.Created}}

$Users | Export-Csv -Path $OutputPath -NoTypeInformation
Write-Host "Report saved: $OutputPath ($($Users.Count) users)"