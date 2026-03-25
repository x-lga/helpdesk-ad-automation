
#!/usr/bin/env python3
"""
ticket_intake.py
================
A simple L1 help desk ticket intake system.
Categorises the issue by keyword matching and outputs resolution steps.

Skills demonstrated: Python fundamentals, IT support workflow, ITIL 4 ticket categorisation.
Cert alignment: CompTIA A+, ITIL 4 Foundation.
"""

import datetime
import json
import random
import string

# --- Resolution database ---
RESOLUTIONS = {
    "password": {
        "category": "Identity & Access",
        "priority": "P3 - Medium",
        "steps": [
            "Verify caller identity (employee ID + manager name).",
            "Check account status in Active Directory: Get-ADUser -Identity <username> -Properties *",
            "If locked out, run: Unlock-ADAccount -Identity <username>",
            "Reset password: Set-ADAccountPassword -Identity <username> -Reset -NewPassword (Read-Host -AsSecureString)",
            "Force password change at next logon: Set-ADUser -Identity <username> -ChangePasswordAtLogon $true",
            "Confirm user can log in. Log ticket as Resolved."
        ],
        "escalate_if": "Account is disabled (not just locked) — requires L2 authorisation to re-enable."
    },
    "internet": {
        "category": "Network Connectivity",
        "priority": "P2 - High",
        "steps": [
            "Ping loopback: ping 127.0.0.1 — verifies TCP/IP stack is functional.",
            "Ping default gateway: ipconfig | findstr Gateway, then ping that IP.",
            "Ping external: ping 8.8.8.8 — if this works but websites fail, issue is DNS.",
            "Flush DNS: ipconfig /flushdns",
            "Run nslookup google.com — check if DNS resolves.",
            "If DHCP issue: ipconfig /release then ipconfig /renew",
            "Last resort: netsh winsock reset, then reboot.",
            "Document all findings and escalate to L2 if unresolved."
        ],
        "escalate_if": "Multiple users affected on same switch — likely upstream issue, escalate immediately."
    },
    "slow": {
        "category": "Performance",
        "priority": "P3 - Medium",
        "steps": [
            "Open Task Manager (Ctrl+Shift+Esc) — check CPU, Memory, Disk columns.",
            "Sort by CPU descending — identify top consuming process.",
            "Check Disk column: sustained 100% disk often = failing drive or Windows Update.",
            "Run Windows Defender quick scan — malware causes performance degradation.",
            "Disable startup programs: Task Manager > Startup tab.",
            "Run Disk Cleanup: cleanmgr.exe",
            "Check Windows Update status: Settings > Update & Security.",
            "Document findings. If RAM consistently >90%: escalate for hardware evaluation."
        ],
        "escalate_if": "Failing SMART disk health indicators — escalate immediately, risk of data loss."
    },
    "printer": {
        "category": "Hardware / Printing",
        "priority": "P3 - Medium",
        "steps": [
            "Check physical connection: USB or network cable seated correctly.",
            "Check printer display for error messages (paper jam, toner, etc.).",
            "Clear print queue: Services > Print Spooler > Stop, delete files in C:\\Windows\\System32\\spool\\PRINTERS, Start spooler.",
            "Remove and re-add printer: Settings > Printers & Scanners > Remove device > Add printer.",
            "Update or rollback printer driver from Device Manager.",
            "Test print from a different application to isolate if it's app-specific.",
            "Check network printer IP hasn't changed — ping printer IP."
        ],
        "escalate_if": "Hardware fault (e.g., roller jam requiring physical repair) — log and assign to on-site tech."
    },
    "vpn": {
        "category": "Remote Access / VPN",
        "priority": "P2 - High",
        "steps": [
            "Confirm: is this one user or multiple? Multiple = server-side, escalate to L2 immediately.",
            "Check local internet connectivity first (ping 8.8.8.8).",
            "Check VPN client logs for specific disconnect reason code.",
            "Try WiFi vs wired connection — WiFi instability causes VPN drops.",
            "Check MTU setting: many VPN clients require MTU 1400 or lower.",
            "Disable any recently installed firewall or security software temporarily to test.",
            "Reinstall VPN client if above steps fail.",
            "Escalate to L2 with complete log file attached."
        ],
        "escalate_if": "Multiple users or recurring drops post-fix — likely server certificate or routing issue."
    },
    "email": {
        "category": "Email / Microsoft 365",
        "priority": "P2 - High",
        "steps": [
            "Check Microsoft 365 service health: admin.microsoft.com > Health > Service health.",
            "Verify user's mailbox exists: M365 Admin > Users > Active users > search user.",
            "Check Outlook connectivity: File > Account Settings > Test Account Settings.",
            "Outlook offline mode: check bottom status bar for 'Working Offline' — click to toggle.",
            "Clear Outlook cache: rename .ost file, restart Outlook.",
            "If web access (OWA) works but Outlook doesn't: client-side issue, reinstall or recreate profile.",
            "Check spam/junk folders for missing emails.",
            "Check mailbox quota: may be full if emails are not sending."
        ],
        "escalate_if": "Mailbox missing entirely or shared mailbox permissions issue — requires M365 admin action."
    },
    "phishing": {
        "category": "Security Incident",
        "priority": "P1 - Critical",
        "steps": [
            "IMMEDIATELY: Tell user — do NOT click any links, do NOT forward, do NOT delete.",
            "Access email via admin console (Exchange Admin / M365) — NOT the user's machine.",
            "Analyse email headers: check Reply-To, Return-Path, X-Originating-IP for spoofing.",
            "Check sender domain spelling carefully (e.g., 'micros0ft.com' vs 'microsoft.com').",
            "Hover over (do not click) any links — check actual URL destination.",
            "Submit suspicious URLs to VirusTotal (virustotal.com) for sandbox analysis.",
            "If confirmed phishing: quarantine the email from all mailboxes.",
            "Document all indicators (sender, subject, URLs, headers) in the ticket.",
            "Send user a training note explaining the phishing indicators.",
            "Escalate to L2/Security team with your complete analysis attached.",
            "ITIL 4: Log as Security Incident. P1 SLA applies."
        ],
        "escalate_if": "User clicked a link or entered credentials — IMMEDIATE escalation, potential credential compromise."
    }
}

def generate_ticket_id():
    """Generate a random ticket ID in format INC-YYYYMMDD-XXXX"""
    date_str = datetime.datetime.now().strftime("%Y%m%d")
    suffix   = ''.join(random.choices(string.digits, k=4))
    return f"INC-{date_str}-{suffix}"

def categorise_issue(description: str) -> dict:
    """Match issue description to a category using keyword lookup."""
    description_lower = description.lower()
    for keyword, resolution in RESOLUTIONS.items():
        if keyword in description_lower:
            return resolution
    return {
        "category": "Uncategorised",
        "priority": "P3 - Medium",
        "steps": [
            "Gather full details: What is the exact error message?",
            "When did this start? Was anything recently installed or changed?",
            "Is this affecting only this user or others?",
            "Attempt a system restart and test again.",
            "Document all findings in detail.",
            "Escalate to L2 with complete information if not resolved in 15 minutes."
        ],
        "escalate_if": "Cannot identify root cause at L1 within 15 minutes."
    }

def create_ticket():
    """Interactive ticket intake process."""
    print("\n" + "="*60)
    print("   L1 HELP DESK TICKET INTAKE SYSTEM")
    print("   ITIL 4 Aligned | CompTIA A+ Framework")
    print("="*60)

    ticket_id   = generate_ticket_id()
    timestamp   = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    print(f"\nTicket ID  : {ticket_id}")
    print(f"Opened     : {timestamp}")
    print("-"*60)

    caller_name  = input("Caller Name       : ").strip()
    caller_dept  = input("Caller Department : ").strip()
    description  = input("Issue Description : ").strip()

    if not description:
        print("ERROR: Issue description cannot be empty.")
        return

    resolution   = categorise_issue(description)

    print("\n" + "="*60)
    print("   TICKET DETAILS")
    print("="*60)
    print(f"Ticket ID  : {ticket_id}")
    print(f"Caller     : {caller_name} ({caller_dept})")
    print(f"Issue      : {description}")
    print(f"Category   : {resolution['category']}")
    print(f"Priority   : {resolution['priority']}")
    print(f"Opened     : {timestamp}")

    print("\n--- RESOLUTION STEPS ---")
    for i, step in enumerate(resolution['steps'], 1):
        print(f"  {i}. {step}")

    print(f"\n--- ESCALATE IF ---")
    print(f"  {resolution['escalate_if']}")

    # Save to JSON log
    ticket_data = {
        "ticket_id"   : ticket_id,
        "timestamp"   : timestamp,
        "caller"      : caller_name,
        "department"  : caller_dept,
        "description" : description,
        "category"    : resolution['category'],
        "priority"    : resolution['priority'],
        "steps"       : resolution['steps'],
        "escalate_if" : resolution['escalate_if'],
        "status"      : "Open"
    }

    log_filename = f"tickets_{datetime.datetime.now().strftime('%Y%m')}.json"
    try:
        with open(log_filename, 'a') as f:
            f.write(json.dumps(ticket_data) + '\n')
        print(f"\nTicket logged to: {log_filename}")
    except Exception as e:
        print(f"WARN: Could not save ticket log — {e}")

    print("\n" + "="*60)

if __name__ == "__main__":
    create_ticket()
