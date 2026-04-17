**Purpose:** L1 triage at scale is inconsistent. Different technicians follow different
steps, ask different questions, classify the same issue at different priorities, and
document at different levels of completeness. This variability leads to missed escalations,
incomplete audit trails, and widely varying resolution times for identical issues.
This Python tool standardises the intake process: every ticket receives a unique ID,
is categorised by keyword matching against a structured resolution database, receives
explicit step-by-step resolution guidance mapped to ITIL 4, has escalation criteria
defined, and is logged to a JSON file for trend analysis. The tool covers seven of the
most common L1 issue types. It is designed to be extended - adding a new issue type
means adding one dictionary entry to RESOLUTIONS.

```python
#!/usr/bin/env python3
"""
ticket_intake.py
================
L1 Help Desk Ticket Intake and Triage System — ITIL 4 Aligned

This tool standardises the L1 ticket intake process by:
  - Generating unique ticket IDs (format: INC-YYYYMMDD-XXXX)
  - Collecting caller information with callback contact
  - Categorising the issue by keyword matching against a structured resolution database
  - Providing step-by-step resolution guidance with escalation criteria for each issue type
  - Classifying by ITIL 4 priority (P1–P4) with SLA response and resolution targets
  - Logging every ticket to a monthly JSON file for trend analysis and audit

The resolution database covers seven of the most common L1 issue types.
Extending coverage: add a new keyword key and resolution dict to RESOLUTIONS.

Cert alignment  : CompTIA A+, ITIL 4 Foundation
Skills shown    : Python fundamentals, ITIL 4 service management, CLI tool development,
                  keyword categorisation, JSON audit logging, structured output
Lab environment : Tested in Proxmox home lab on Ubuntu 22.04 and Windows 10
"""

import datetime
import json
import random
import string
import os


# ─────────────────────────────────────────────────────────────────────────────
#  RESOLUTION DATABASE
#  Each key is a keyword matched against the caller's issue description.
#  The value is a dict with: category, priority, SLA targets, resolution steps,
#  and escalation criteria.
# ─────────────────────────────────────────────────────────────────────────────
RESOLUTIONS: dict = {

    "password": {
        "category"       : "Identity & Access Management",
        "priority"       : "P3 — Medium",
        "sla_response"   : "4 hours",
        "sla_resolution" : "24 hours",
        "steps": [
            "VERIFY IDENTITY: Confirm caller identity BEFORE any account action. "
            "Acceptable methods: employee ID number, manager name, callback to desk phone on file.",
            "CHECK ACCOUNT STATUS: Run Unlock-ADUserAccount.ps1 to see full account state "
            "before deciding on reset vs unlock vs escalate.",
            "IF LOCKED: Run Unlock-ADUserAccount.ps1 to unlock. Test login. "
            "If just locked (not expired): unlock may be all that is needed.",
            "IF EXPIRED or full reset needed: Run Reset-ADUserPassword.ps1 -Username <samaccountname>. "
            "Script generates a random temporary password and forces change at next logon.",
            "COMMUNICATE: Relay the temporary password by PHONE — never by email or chat.",
            "CONFIRM: Ask user to attempt login and confirm success before closing the ticket.",
            "DOCUMENT: Record identity verification method, steps taken, and resolution outcome."
        ],
        "escalate_if": "Account is DISABLED (not locked) — requires L2 authorisation. "
                       "Do NOT re-enable without approval from the user's manager and L2."
    },

    "internet": {
        "category"       : "Network Connectivity",
        "priority"       : "P2 — High (single user) | P1 — Critical (multiple users)",
        "sla_response"   : "1 hour (P2) | 15 minutes (P1)",
        "sla_resolution" : "8 hours (P2) | 4 hours (P1)",
        "steps": [
            "SCOPE FIRST: Ask 'Is anyone else affected?' — if multiple users: P1, escalate immediately. "
            "Do not spend time on client-side steps for a network-wide issue.",
            "LAYER 1 (Physical): Check NIC lights — link (solid) + activity (blinking). "
            "Reseat or swap ethernet cable. Confirm switch port LED shows link.",
            "LAYER 3 (IP): Run ipconfig /all — confirm valid IP (not 169.254.x.x), gateway, DNS.",
            "PING TEST SEQUENCE: "
            "ping 127.0.0.1 (TCP/IP stack) → "
            "ping <gateway> (local network) → "
            "ping 8.8.8.8 (internet routing) → "
            "ping google.com (DNS resolution).",
            "INTERPRET: "
            "Loopback fails = TCP/IP corrupt (netsh winsock reset, restart). "
            "Gateway fails = local network/DHCP issue. "
            "8.8.8.8 fails = routing/WAN issue (escalate). "
            "google.com fails only = DNS issue (see DNS procedure, run ipconfig /flushdns).",
            "DHCP: If IP is 169.254.x.x run: ipconfig /release && ipconfig /renew.",
            "LAST RESORT (requires restart): netsh winsock reset, netsh int ip reset, "
            "ipconfig /flushdns, ipconfig /release, ipconfig /renew — then restart.",
            "DOCUMENT: Record all ping results and steps taken before escalating."
        ],
        "escalate_if": "Multiple users affected on the same network segment, "
                       "or issue persists after winsock reset and restart."
    },

    "slow": {
        "category"       : "Performance Degradation",
        "priority"       : "P3 — Medium",
        "sla_response"   : "4 hours",
        "sla_resolution" : "24 hours",
        "steps": [
            "OPEN Task Manager (Ctrl+Shift+Esc). Click 'More Details' if in compact view.",
            "SORT BY CPU: Identify the top-consuming process. Is it a known application or unknown?",
            "CHECK DISK COLUMN: Sustained 100% disk = failing drive, Windows Update indexing, "
            "or malware. This is a common cause of 'computer is slow' reports.",
            "CHECK MEMORY: If physical RAM consistently >85% utilised, "
            "machine needs more RAM — document for L2 hardware evaluation.",
            "MALWARE: Run Windows Defender Quick Scan. Malware is a frequent cause of "
            "sudden performance degradation.",
            "STARTUP: Disable unnecessary startup programs — Task Manager > Startup tab. "
            "This takes effect on next restart.",
            "DISK CLEANUP: Run cleanmgr.exe. Select all categories including System Files. "
            "Also clear C:\\Windows\\Temp and %TEMP%.",
            "WINDOWS UPDATE: Check Settings > Windows Update for stuck updates. "
            "A stuck update can saturate disk I/O and CPU.",
            "DOCUMENT: Note top CPU/disk process name, RAM usage percentage, "
            "free disk space, Defender scan result, and action taken."
        ],
        "escalate_if": "SMART disk health failure indicators present, RAM consistently >90% "
                       "with no runaway process, or hardware replacement required."
    },

    "printer": {
        "category"       : "Hardware — Printing",
        "priority"       : "P3 — Medium",
        "sla_response"   : "4 hours",
        "sla_resolution" : "24 hours",
        "steps": [
            "PHYSICAL: Check USB or network cable at both ends. Check printer display panel "
            "for error messages (paper jam, toner low, cover open).",
            "POWER CYCLE: Turn printer off, wait 30 seconds, turn back on.",
            "PRINT QUEUE: Clear stuck jobs — "
            "Stop Print Spooler service → "
            "delete all files in C:\\Windows\\System32\\spool\\PRINTERS → "
            "Start Print Spooler. (Or run Clear-PrintQueue.ps1)",
            "REINSTALL: Remove and re-add the printer — Settings > Printers & Scanners > "
            "click printer > Remove > Add a printer or scanner.",
            "DRIVER: Right-click the printer in Device Manager > Update Driver. "
            "If update fails: download driver directly from manufacturer website.",
            "TEST: Print a test page from Notepad. If Notepad prints but the application does not: "
            "the issue is application-specific, not the printer.",
            "NETWORK PRINTER: Ping the printer IP address. If unreachable: "
            "check network cable, verify IP has not changed (DHCP lease issue)."
        ],
        "escalate_if": "Physical hardware fault requiring physical repair "
                       "(roller jam, fuser failure, paper path blockage) — escalate to on-site tech."
    },

    "vpn": {
        "category"       : "Remote Access — VPN",
        "priority"       : "P2 — High (single user) | P1 — Critical (multiple users)",
        "sla_response"   : "1 hour (P2) | 15 minutes (P1)",
        "sla_resolution" : "8 hours (P2) | 4 hours (P1)",
        "steps": [
            "SCOPE FIRST — MANDATORY: Ask 'Are other remote users also having VPN issues?' "
            "Multiple users = P1 server-side issue. Escalate IMMEDIATELY. "
            "Do not spend time on client-side steps.",
            "LOCAL INTERNET: Confirm local internet works — ping 8.8.8.8. "
            "If ping fails: local connectivity issue, not VPN. See internet procedure first.",
            "VPN CLIENT LOGS: Locate and review VPN logs for the exact error code/message. "
            "Cisco AnyConnect: %ProgramData%\\Cisco\\...\\AnyConnect.log | "
            "GlobalProtect: %APPDATA%\\Palo Alto Networks\\GlobalProtect\\PanGPS.log | "
            "OpenVPN: C:\\Program Files\\OpenVPN\\log\\ | "
            "WireGuard: Show Log in the WireGuard app.",
            "MTU: VPN adds overhead — large packets get fragmented and dropped. "
            "Test: ping 8.8.8.8 -f -l 1400 (does it succeed?). "
            "If fails at 1400, try 1300. "
            "Fix: netsh interface ipv4 set subinterface 'Wi-Fi' mtu=1400 store=persistent",
            "WIRED VS WIFI: Ask user to connect via ethernet cable and retry. "
            "If VPN is stable on wired but not wireless: WiFi instability is the cause "
            "(driver update, move closer to AP, or use wired permanently).",
            "REINSTALL: If all above fail, uninstall and reinstall the VPN client.",
            "ESCALATE: Provide L2 with: VPN client name and version, full log file, "
            "scope check result, MTU test result, wired vs wireless result, "
            "and time/duration of disconnections."
        ],
        "escalate_if": "Multiple users affected, VPN server certificate expiry, "
                       "routing change required, or recurring drops within 24 hours of fix."
    },

    "email": {
        "category"       : "Email — Microsoft 365",
        "priority"       : "P2 — High",
        "sla_response"   : "1 hour",
        "sla_resolution" : "8 hours",
        "steps": [
            "SERVICE HEALTH FIRST: Check Microsoft 365 Admin Centre > Health > Service Health. "
            "If M365 is showing an active incident for Exchange: it is Microsoft's issue, "
            "not a local issue. Document and wait. Do not waste time on client steps.",
            "MAILBOX EXISTS: Verify in M365 Admin > Users > Active Users that the mailbox exists "
            "and the user has an Exchange licence assigned.",
            "OWA TEST: Can the user access email at outlook.office.com? "
            "If OWA works and Outlook does not: client-side issue, not server.",
            "WORKING OFFLINE: Check the Outlook status bar (bottom right) for 'Working Offline'. "
            "Click it to toggle online. This is the most common 'Outlook not receiving' cause.",
            "CONNECTIVITY TEST: In Outlook: File > Account Settings > Account Settings > "
            "double-click the account > Test Account Settings. Review errors.",
            "PROFILE REBUILD: If OWA works but Outlook consistently fails: "
            "rename the .ost file (close Outlook first), reopen Outlook to rebuild. "
            "Location: %LOCALAPPDATA%\\Microsoft\\Outlook\\",
            "QUOTA: Check if the mailbox is full. A full mailbox cannot receive. "
            "M365 Admin > Users > [user] > Mail tab > Mailbox usage.",
            "JUNK / SPAM: Missing emails may be in Junk Email folder. "
            "Check and add legitimate senders to the safe senders list."
        ],
        "escalate_if": "Mailbox missing entirely, licence assignment issue, "
                       "shared mailbox permissions, or distribution group membership changes — "
                       "all require M365 admin access that exceeds L1 scope."
    },

    "phishing": {
        "category"       : "Security Incident — Suspected Phishing Email",
        "priority"       : "P1 — Critical if user clicked or entered credentials | P2 — High if reported before clicking",
        "sla_response"   : "15 minutes (P1) | 1 hour (P2)",
        "sla_resolution" : "4 hours (P1) | 8 hours (P2)",
        "steps": [
            "IMMEDIATE — TELL USER: 'Do NOT click any links, do NOT open any attachments, "
            "do NOT forward the email, do NOT delete it yet.'",
            "CLASSIFY: Ask 'Did you click any link or enter any credentials?' "
            "If YES: this is P1. Skip to Step 9 immediately.",
            "ACCESS EMAIL VIA ADMIN CONSOLE: Do NOT access the email from the user's machine. "
            "Use Exchange Admin Centre or M365 Admin > Search for the message.",
            "ANALYSE SENDER: Check From address (is the domain correct?), "
            "Reply-To address (does it differ from From?), Return-Path header.",
            "ANALYSE HEADERS: Extract full email headers. Check: "
            "SPF result (pass/fail/softfail), DKIM result (pass/fail), DMARC result. "
            "Check originating IP and whether it matches the claimed sender domain.",
            "ANALYSE URLS: Do NOT click. Right-click any links → Copy link address. "
            "Submit to: virustotal.com (URL tab) and urlscan.io. "
            "Check domain registration age with whois — newly registered = high risk.",
            "ANALYSE ATTACHMENTS: Do NOT open. Submit the file hash to virustotal.com. "
            "If no hash available: submit the file to VirusTotal in a controlled environment only.",
            "IF CONFIRMED PHISHING (P2 — user did not click): "
            "Quarantine the email from all mailboxes (M365 Admin > Content Search > purge), "
            "Block the sender domain at the email gateway, "
            "Document all indicators (sender, subject, URLs, IPs, header findings), "
            "Send user education note, "
            "Escalate to L2 Security with full analysis attached.",
            "IF P1 — USER CLICKED OR ENTERED CREDENTIALS: "
            "IMMEDIATELY disable the user's account: Disable-ADAccount -Identity <username>. "
            "IMMEDIATELY revoke all active M365/Entra ID sessions: "
            "Azure Portal > Entra ID > Users > [user] > Revoke Sessions. "
            "PHONE CALL to L2 Security team — do not wait for ticket queue. "
            "Do NOT log the user out of their machine (forensic preservation). "
            "Document: exact time reported, time of click if known, "
            "credentials entered (M365 only? AD? VPN?). "
            "Do NOT re-enable the account without L2 Security sign-off."
        ],
        "escalate_if": "IMMEDIATE and MANDATORY escalation if user clicked any link "
                       "or entered credentials. This is a P1 Security Incident — "
                       "potential account compromise requiring incident response procedures."
    }
}


# ─────────────────────────────────────────────────────────────────────────────
#  HELPER FUNCTIONS
# ─────────────────────────────────────────────────────────────────────────────

def generate_ticket_id() -> str:
    """Generate a unique ticket ID: INC-YYYYMMDD-XXXX"""
    date_str = datetime.datetime.now().strftime("%Y%m%d")
    suffix   = "".join(random.choices(string.digits, k=4))
    return f"INC-{date_str}-{suffix}"


def categorise_issue(description: str) -> tuple:
    """
    Match the issue description against the RESOLUTIONS database by keyword.
    Returns (resolution_dict, matched_keyword).
    Falls back to a generic uncategorised resolution if no keyword matches.
    """
    desc_lower = description.lower()

    for keyword, resolution in RESOLUTIONS.items():
        if keyword in desc_lower:
            return resolution, keyword

    # No keyword match — return generic resolution
    generic = {
        "category"       : "Uncategorised — Manual Investigation Required",
        "priority"       : "P3 — Medium (reassess after investigation)",
        "sla_response"   : "4 hours",
        "sla_resolution" : "24 hours",
        "steps": [
            "GATHER: Ask for the exact error message or symptom — quote it word for word.",
            "TIMELINE: When did this start? What changed recently "
            "(software installed, Windows Update, hardware moved, password changed)?",
            "SCOPE: Is this affecting only this user/device, or others as well?",
            "REPRODUCE: Ask the user to reproduce the issue while you observe (remote or in person).",
            "RESTART: If not already done, perform a full system restart and test again.",
            "DOCUMENT: Record all findings with timestamps — symptoms, steps, results.",
            "ESCALATE: If root cause not identified within 15 minutes at L1, escalate to L2 "
            "with all documentation attached."
        ],
        "escalate_if": "Root cause not identified within the L1 SLA window for the priority level."
    }
    return generic, "unknown"


def log_ticket(ticket_data: dict) -> str:
    """
    Append the ticket record to a monthly JSON log file.
    Returns the log filename.
    Each line in the file is a complete JSON object (JSON Lines format).
    """
    log_filename = f"helpdesk_tickets_{datetime.datetime.now().strftime('%Y%m')}.json"
    try:
        with open(log_filename, "a", encoding="utf-8") as f:
            f.write(json.dumps(ticket_data, ensure_ascii=False) + "\n")
    except Exception as e:
        print(f"  WARNING: Could not write to log file '{log_filename}': {e}")
    return log_filename


def print_divider(char: str = "═", width: int = 65) -> None:
    print(char * width)


# ─────────────────────────────────────────────────────────────────────────────
#  MAIN TICKET INTAKE FUNCTION
# ─────────────────────────────────────────────────────────────────────────────

def create_ticket() -> None:
    """Interactive L1 help desk ticket intake process."""

    print("\n")
    print_divider()
    print("  L1 HELP DESK TICKET INTAKE SYSTEM")
    print("  ITIL 4 Aligned | CompTIA A+ Portfolio Project")
    print_divider()

    ticket_id = generate_ticket_id()
    timestamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    print(f"\n  Ticket ID   : {ticket_id}")
    print(f"  Opened at   : {timestamp}")
    print_divider("─")

    # Collect caller information
    caller_name = input("  Caller full name        : ").strip()
    caller_dept = input("  Caller department       : ").strip()
    caller_ext  = input("  Callback phone/ext      : ").strip()
    asset_name  = input("  Affected computer name  : ").strip()
    description = input("  Issue description       : ").strip()

    if not description:
        print("  ERROR: Issue description cannot be empty.")
        return

    # Categorise the issue
    resolution, matched_keyword = categorise_issue(description)

    # Display the structured ticket
    print("\n")
    print_divider()
    print("  TICKET — CATEGORISED AND READY FOR TRIAGE")
    print_divider()
    print(f"  Ticket ID        : {ticket_id}")
    print(f"  Opened           : {timestamp}")
    print(f"  Caller           : {caller_name} ({caller_dept}) — {caller_ext}")
    print(f"  Affected Asset   : {asset_name if asset_name else 'Not specified'}")
    print(f"  Description      : {description}")
    print(f"  Category         : {resolution['category']}")
    print(f"  Priority         : {resolution['priority']}")
    print(f"  SLA — Response   : {resolution['sla_response']}")
    print(f"  SLA — Resolve    : {resolution['sla_resolution']}")
    if matched_keyword != "unknown":
        print(f"  Matched keyword  : '{matched_keyword}'")
    else:
        print(f"  Matched keyword  : none — manual categorisation required")

    print_divider("─")
    print("  RESOLUTION STEPS")
    print_divider("─")
    for i, step in enumerate(resolution["steps"], 1):
        # Word-wrap long steps at 60 chars for readability
        print(f"  {i:02d}. {step}")
        print()

    print_divider("─")
    print(f"  ESCALATE IF: {resolution['escalate_if']}")
    print_divider("─")

    # Log the ticket to JSON
    ticket_record = {
        "ticket_id"      : ticket_id,
        "timestamp"      : timestamp,
        "caller_name"    : caller_name,
        "caller_dept"    : caller_dept,
        "caller_callback": caller_ext,
        "asset_name"     : asset_name,
        "description"    : description,
        "matched_keyword": matched_keyword,
        "category"       : resolution["category"],
        "priority"       : resolution["priority"],
        "sla_response"   : resolution["sla_response"],
        "sla_resolution" : resolution["sla_resolution"],
        "steps"          : resolution["steps"],
        "escalate_if"    : resolution["escalate_if"],
        "status"         : "Open"
    }

    log_file = log_ticket(ticket_record)
    print(f"  Ticket logged to : {log_file}")
    print_divider()
    print()


# ─────────────────────────────────────────────────────────────────────────────
#  ENTRY POINT
# ─────────────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    create_ticket()
