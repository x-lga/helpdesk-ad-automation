
```powershell
<#
.SYNOPSIS
    Bulk creates Active Directory users from a CSV file.

.DESCRIPTION
    Reads a CSV with columns: FirstName, LastName, Department, Title, Manager
    Creates AD accounts with standardised UPN, display name, and OU placement.
    Logs all actions to a timestamped file.

.PARAMETER CsvPath
    Path to the input CSV file.

.PARAMETER OUPath
    Distinguished Name of the target Organisational Unit.

.EXAMPLE
    .\New-BulkADUsers.ps1 -CsvPath "C:\users.csv" -OU "OU=Staff,DC=contoso,DC=local"

.NOTES
    Requires: ActiveDirectory module (RSAT)
    Run as: Domain Admin or delegated account with User Create rights
    Tested on: Windows Server 2022 / Windows 10 with RSAT
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$CsvPath,

    [Parameter(Mandatory=$true)]
    [string]$OUPath
)

# --- Configuration ---
$Domain        = "contoso.local"
$DefaultPW     = "Welcome@12345!"       # Force change on first login
$LogFile       = "C:\Logs\BulkUserCreate_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$SmtpServer    = "smtp.contoso.local"
$AlertEmail    = "it-alerts@contoso.local"

# --- Ensure log directory exists ---
if (-not (Test-Path "C:\Logs")) {
    New-Item -ItemType Directory -Path "C:\Logs" | Out-Null
}

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $Entry = "[$Timestamp] [$Level] $Message"
    Add-Content -Path $LogFile -Value $Entry
    Write-Host $Entry
}

# --- Import ActiveDirectory module ---
Import-Module ActiveDirectory -ErrorAction Stop

# --- Read CSV ---
if (-not (Test-Path $CsvPath)) {
    Write-Log "CSV file not found: $CsvPath" -Level "ERROR"
    exit 1
}

$Users = Import-Csv -Path $CsvPath
Write-Log "Loaded $($Users.Count) users from $CsvPath"

$SuccessCount = 0
$ErrorCount   = 0

foreach ($User in $Users) {

    $FirstName   = $User.FirstName.Trim()
    $LastName    = $User.LastName.Trim()
    $Department  = $User.Department.Trim()
    $Title       = $User.Title.Trim()
    $Manager     = $User.Manager.Trim()

    # --- Build standard username: first initial + last name (lowercase) ---
    $Username    = ($FirstName.Substring(0,1) + $LastName).ToLower()
    $UPN         = "$Username@$Domain"
    $DisplayName = "$FirstName $LastName"

    try {
        # Check if user already exists
        if (Get-ADUser -Filter {SamAccountName -eq $Username} -ErrorAction SilentlyContinue) {
            Write-Log "SKIP: User $Username already exists." -Level "WARN"
            continue
        }

        $SecurePassword = ConvertTo-SecureString $DefaultPW -AsPlainText -Force

        New-ADUser `
            -Name              $DisplayName `
            -GivenName         $FirstName `
            -Surname           $LastName `
            -SamAccountName    $Username `
            -UserPrincipalName $UPN `
            -DisplayName       $DisplayName `
            -Department        $Department `
            -Title             $Title `
            -AccountPassword   $SecurePassword `
            -ChangePasswordAtLogon $true `
            -Enabled           $true `
            -Path              $OUPath

        Write-Log "SUCCESS: Created user $Username ($DisplayName) in $OUPath"
        $SuccessCount++

    } catch {
        Write-Log "ERROR: Failed to create $Username — $($_.Exception.Message)" -Level "ERROR"
        $ErrorCount++
    }
}

Write-Log "--- SUMMARY: $SuccessCount created, $ErrorCount failed. Log: $LogFile ---"
```
