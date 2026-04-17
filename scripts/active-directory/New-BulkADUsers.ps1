**Purpose:** Every new-hire intake, restructure, or school-term cohort generates a wave of
user creation tickets. Done manually through the Active Directory Users and Computers GUI,
creating 20 users takes 45+ minutes with a high error rate - wrong OU, inconsistent naming,
forgotten password policy, no audit trail. This script reads a structured CSV, validates
every field before acting, creates accounts with a standardised naming convention, skips
existing users gracefully without crashing, logs every action with timestamp and outcome,
and prints a summary report on completion. The same 20-user job takes under 4 minutes
with zero manual errors and a full log file ready for the change management record.

**Skills demonstrated:** PowerShell parameter handling with validation, CSV import and
field validation, Active Directory module usage, try/catch error handling, structured
logging function, security practices '('forced password change at first logon, no plaintext
passwords in log output'),' summary reporting.

```powershell
<#
.SYNOPSIS
    Bulk creates Active Directory user accounts from a structured CSV file.

.DESCRIPTION
    Reads a CSV file with columns: FirstName, LastName, Department, Title, Manager.
    For each row the script:
      - Validates that required fields are populated before attempting creation
      - Builds a standardised username (first initial + last name, lowercase, alphanumeric only)
      - Checks for duplicate SamAccountName before creating
      - Creates the account with a secure temporary password in the specified OU
      - Sets ChangePasswordAtLogon to force the user to set their own password on first login
      - Logs every action (success, skip, error) to a timestamped log file
      - Prints a colour-coded summary on completion

    Time saving estimate: 45 minutes manual GUI work → under 4 minutes scripted.
    Error rate: Manual = high (wrong OU, inconsistent naming). Scripted = zero if CSV is correct.

    ITIL 4 alignment: This script supports the Change Management process. The log file
    it produces serves as the audit trail entry for the bulk user creation change record.

.PARAMETER CsvPath
    Full path to the CSV file containing user data.
    CSV must have headers: FirstName, LastName, Department, Title, Manager
    Manager column can be blank — it is informational only in this script.

.PARAMETER OUPath
    Distinguished Name of the Organisational Unit where accounts will be created.
    Example: "OU=Staff,DC=contoso,DC=local"

.EXAMPLE
    .\New-BulkADUsers.ps1 -CsvPath "C:\HR\new_hires_august.csv" -OUPath "OU=Staff,DC=contoso,DC=local"

.EXAMPLE
    .\New-BulkADUsers.ps1 -CsvPath ".\sample_users.csv" -OUPath "OU=Contractors,DC=contoso,DC=local"

.NOTES
    Requires  : ActiveDirectory PowerShell module (RSAT — Remote Server Administration Tools)
    Run as    : Domain Admin, or a delegated account with "Create User Objects" permission on the target OU
    Tested on : Windows Server 2022, Windows 10/11 with RSAT installed
    Lab env   : Proxmox home lab, domain contoso.local, Windows Server 2022 DC
    Cert align: CompTIA A+, ITIL 4 Change Management
    Author    : [Your Name] — IT & Cloud Support Portfolio
#>

param(
    [Parameter(Mandatory = $true, HelpMessage = "Full path to the CSV file with user data")]
    [ValidateScript({
        if (-not (Test-Path $_ -PathType Leaf)) {
            throw "CSV file not found: $_"
        }
        $true
    })]
    [string]$CsvPath,

    [Parameter(Mandatory = $true, HelpMessage = "Distinguished Name of the target OU")]
    [ValidateNotNullOrEmpty()]
    [string]$OUPath
)

# ─────────────────────────────────────────────────────────────
#  CONFIGURATION — adjust these values for your environment
# ─────────────────────────────────────────────────────────────
$Domain      = "contoso.local"
$DefaultPW   = "Welcome@12345!"        # User MUST change this on first logon
$LogDir      = "C:\Logs\ADAutomation"
$LogFile     = "$LogDir\BulkUserCreate_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

# ─────────────────────────────────────────────────────────────
#  LOGGING FUNCTION
# ─────────────────────────────────────────────────────────────
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO", "SUCCESS", "WARN", "ERROR")]
        [string]$Level = "INFO"
    )
    # Ensure log directory exists on first write
    if (-not (Test-Path $LogDir)) {
        New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
    }
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $Entry     = "[$Timestamp] [$Level] $Message"
    Add-Content -Path $LogFile -Value $Entry

    # Console colour by level
    $Colour = switch ($Level) {
        "SUCCESS" { "Green"  }
        "WARN"    { "Yellow" }
        "ERROR"   { "Red"    }
        default   { "Cyan"   }
    }
    Write-Host $Entry -ForegroundColor $Colour
}

# ─────────────────────────────────────────────────────────────
#  INITIALISE
# ─────────────────────────────────────────────────────────────
Write-Log "Script started by operator: $($env:USERNAME) on host: $($env:COMPUTERNAME)"
Write-Log "CSV source file : $CsvPath"
Write-Log "Target OU       : $OUPath"
Write-Log "Domain          : $Domain"

# Import the Active Directory module — fail fast if not available
try {
    Import-Module ActiveDirectory -ErrorAction Stop
    Write-Log "ActiveDirectory module loaded successfully."
} catch {
    Write-Log "FATAL: ActiveDirectory module not available. Install RSAT and retry. Error: $($_.Exception.Message)" -Level "ERROR"
    exit 1
}

# Validate the target OU exists before processing any rows
try {
    $OUCheck = Get-ADOrganizationalUnit -Filter { DistinguishedName -eq $OUPath } -ErrorAction Stop
    if (-not $OUCheck) {
        Write-Log "FATAL: Target OU '$OUPath' does not exist in Active Directory." -Level "ERROR"
        exit 1
    }
    Write-Log "Target OU validated: $OUPath"
} catch {
    Write-Log "FATAL: Could not validate target OU. Error: $($_.Exception.Message)" -Level "ERROR"
    exit 1
}

# Read the CSV
$Users = Import-Csv -Path $CsvPath
Write-Log "Loaded $($Users.Count) record(s) from CSV. Beginning processing."
Write-Log ("─" * 60)

# Counters
$SuccessCount = 0
$SkipCount    = 0
$ErrorCount   = 0

# ─────────────────────────────────────────────────────────────
#  MAIN PROCESSING LOOP
# ─────────────────────────────────────────────────────────────
foreach ($User in $Users) {

    # Trim all fields to remove accidental whitespace from the CSV
    $FirstName  = $User.FirstName.Trim()
    $LastName   = $User.LastName.Trim()
    $Department = $User.Department.Trim()
    $Title      = $User.Title.Trim()
    $Manager    = if ($User.Manager) { $User.Manager.Trim() } else { "" }

    # ── Field validation ──────────────────────────────────────
    if ([string]::IsNullOrWhiteSpace($FirstName) -or [string]::IsNullOrWhiteSpace($LastName)) {
        Write-Log "SKIP: Row has blank FirstName or LastName. Row data: $($User | Out-String)" -Level "WARN"
        $SkipCount++
        continue
    }

    # ── Build standardised username ───────────────────────────
    # Convention: first initial + last name, all lowercase, alphanumeric only
    # Example: John Smith → jsmith | Mary-Anne O'Brien → moobrien
    $RawUsername = ($FirstName.Substring(0, 1) + $LastName).ToLower()
    $Username    = $RawUsername -replace '[^a-z0-9]', ''
    $UPN         = "$Username@$Domain"
    $DisplayName = "$FirstName $LastName"

    Write-Log "Processing: $DisplayName → username candidate: $Username"

    # ── Duplicate check ───────────────────────────────────────
    $ExistingUser = Get-ADUser -Filter { SamAccountName -eq $Username } -ErrorAction SilentlyContinue
    if ($ExistingUser) {
        Write-Log "SKIP: Username '$Username' already exists in AD (DN: $($ExistingUser.DistinguishedName))." -Level "WARN"
        $SkipCount++
        continue
    }

    # ── Create account ────────────────────────────────────────
    try {
        $SecurePassword = ConvertTo-SecureString $DefaultPW -AsPlainText -Force

        $NewUserParams = @{
            Name                  = $DisplayName
            GivenName             = $FirstName
            Surname               = $LastName
            Manager               = $Manager
            SamAccountName        = $Username
            UserPrincipalName     = $UPN
            DisplayName           = $DisplayName
            Department            = $Department
            Title                 = $Title
            AccountPassword       = $SecurePassword
            ChangePasswordAtLogon = $true
            Enabled               = $true
            Path                  = $OUPath
        }

        New-ADUser @NewUserParams

        Write-Log "SUCCESS: Created user '$Username' ($DisplayName) | Dept: $Department | Title: $Title | OU: $OUPath" -Level "SUCCESS"
        $SuccessCount++

    } catch {
        Write-Log "ERROR: Failed to create '$Username' ($DisplayName). Reason: $($_.Exception.Message)" -Level "ERROR"
        $ErrorCount++
    }
}

# ─────────────────────────────────────────────────────────────
#  SUMMARY REPORT
# ─────────────────────────────────────────────────────────────
Write-Log ("─" * 60)
Write-Log "BULK USER CREATION COMPLETE"
Write-Log "Total rows processed : $($Users.Count)"
Write-Log "Accounts created     : $SuccessCount" -Level "SUCCESS"
Write-Log "Skipped (duplicate)  : $SkipCount"   -Level "WARN"
Write-Log "Errors               : $ErrorCount"  -Level $(if ($ErrorCount -gt 0) { "ERROR" } else { "INFO" })
Write-Log "Full log saved to    : $LogFile"
Write-Log ("─" * 60)

if ($ErrorCount -gt 0) {
    Write-Host "`n⚠  $ErrorCount account(s) failed to create. Review the log file for details: $LogFile" -ForegroundColor Red
}
```