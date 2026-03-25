
```markdown
# helpdesk-ad-automation

PowerShell and Python scripts for Active Directory user lifecycle management, L1 help desk ticket automation, and IT support workflows.

Built as part of a real-world IT support portfolio demonstrating competency across CompTIA A+, Active Directory administration, PowerShell scripting, and ITIL 4 service management.

---

## Contents

| Script | Purpose | Cert Alignment |
|--------|---------|----------------|
| `New-BulkADUsers.ps1` | Bulk create AD users from CSV with logging | A+, PowerShell |
| `Reset-ADUserPassword.ps1` | L1 password reset with unlock check | A+, AD |
| `Unlock-ADUserAccount.ps1` | Account unlock with status diagnostics | A+, AD |
| `Export-ADUserReport.ps1` | Full AD user audit report to CSV | A+, ITIL 4 Change Mgmt |
| `Watch-DiskSpace.ps1` | Disk monitoring with email alert | A+, Proactive Event Mgmt |
| `Invoke-RemoteSession.ps1` | Remote PS session / command execution | A+, Net+ |
| `ticket_intake.py` | Python L1 ticket intake with auto-categorisation | A+, ITIL 4 |
| `itil4-ticket-workflow.md` | ITIL 4 priority matrix and escalation guide | ITIL 4 Foundation |

---

## Skills Demonstrated

- **Active Directory:** User lifecycle (create, reset, unlock, audit), OU management, delegation principles
- **PowerShell:** Parameter handling, error handling, logging, CSV import/export, email alerting, remote sessions
- **Python:** CLI tool development, keyword categorisation, JSON logging
- **ITIL 4:** Incident vs Problem vs Change, priority matrix (P1–P4), SLA-aligned escalation criteria
- **Help Desk Workflow:** L1 triage methodology, escalation documentation, caller verification

---

## Lab Environment

All scripts tested in a Proxmox-hosted Windows Server 2022 domain controller environment:
- Domain: contoso.local
- Domain Controller: Windows Server 2022
- Client endpoints: Windows 10/11 VMs
- RSAT tools installed for AD module

---

## How to Run

### Prerequisites
- Windows machine with RSAT (Remote Server Administration Tools) installed
- ActiveDirectory PowerShell module
- Domain Admin or delegated account for AD scripts
- Python 3.x for ticket_intake.py

### Run a script

```powershell
# Bulk user creation
.\scripts\active-directory\New-BulkADUsers.ps1 -CsvPath ".\sample_users.csv" -OUPath "OU=Staff,DC=contoso,DC=local"

# Password reset
.\scripts\active-directory\Reset-ADUserPassword.ps1 -Username jsmith

# Disk monitoring
.\scripts\disk-monitoring\Watch-DiskSpace.ps1
```

```bash
# Ticket intake (Python)
python3 scripts/ticket-intake/ticket_intake.py
```

---

## Outcome

These scripts reduce repetitive administrative task time by an estimated 60% compared to manual GUI-based processes. All actions are logged with timestamps for audit trail compliance — aligned with ITIL 4 Change and Incident Management documentation requirements.
```