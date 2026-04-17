# ITIL 4 Ticket Workflow - L1 Help Desk Reference

This document defines the ticket management workflow used in conjunction with the
helpdesk-ad-automation scripts and the ticket_intake.py tool. It is based on ITIL 4
Incident Management practices and is suitable for use as a day-one reference document
for any L1 help desk technician.

---

## Ticket Priority Matrix

Every ticket must be assigned a priority at intake. Priority determines response time,
resolution target, and escalation urgency. Do not default everything to P3 because it
feels safer - P1 and P2 exist for a reason, and failing to classify correctly means
SLAs are breached without being measured.

| Priority | Label | Definition | Response Target | Resolution Target |
|----------|-------|-----------|----------------|------------------|
| P1 | Critical | Complete service outage. Active security incident. Data loss or breach confirmed or suspected. Multiple users or sites affected. Revenue impact or regulatory exposure. | 15 minutes | 4 hours |
| P2 | High | Significant degradation. Single critical user or service impacted. Business operations affected but not stopped. | 1 hour | 8 hours |
| P3 | Medium | Single user affected with available workaround. Productivity reduced but not stopped. | 4 hours | 24 hours |
| P4 | Low | Cosmetic issue. Non-urgent request. No productivity impact. Enhancement or service request. | 8 hours | 72 hours |

**Important:** All SLA times are measured from the moment the ticket is logged - not from
when L1 begins working on it. If a ticket sits in the queue for 45 minutes before being
picked up and the SLA is 1 hour, there are only 15 minutes left.

---

## ITIL 4 Record Types - Incident, Problem, and Change

These three record types are distinct. Using the wrong type for the wrong situation is a
common mistake that causes confusion in reporting and root cause management.

| Record Type | Definition | When to create | L1 Action |
|-------------|-----------|---------------|-----------|
| **Incident** | An unplanned interruption to a service, or a reduction in the quality of a service. | Whenever a user reports something that was working and is now not working, or is working poorly. | Restore service as fast as possible. Log, triage, apply known resolution, escalate if needed. Document everything. |
| **Problem** | The underlying root cause of one or more incidents. | When the same incident type recurs (e.g., same user locked out three times this week). When multiple users experience the same symptom. When L2/L3 identifies a root cause during investigation. | Raise a separate Problem ticket. Assign to L2/L3. Document known workarounds while root cause investigation is underway. Do not close the Problem until root cause is confirmed and fixed. |
| **Change** | A planned, authorised modification to infrastructure, systems, or services. | Any time something in the infrastructure is intentionally modified as a result of an incident, problem, or request. | Log an RFC (Request for Change). Reference the originating Incident or Problem number. Follow the change calendar. Never implement infrastructure changes during incident response without creating a Change record, even in emergencies. |

**Practical example:**
- User calls: account locked out → **Incident** (unlock account, restore access)
- Same user calls three times in two weeks with the same lockout → **Problem** (raise Problem, investigate root cause - saved credentials on phone, mapped drive with old password, etc.)
- Fix requires a policy change to increase lockout threshold → **Change** (RFC to modify Group Policy, tested, approved, documented)

---

## L1 Escalation Criteria

Escalate to L2 **immediately** when any of the following conditions are met:

1. **SLA breach:** The ticket has been open longer than the response target for its priority and is not resolved
2. **Root cause unidentifiable:** L1 cannot determine the cause within the allocated triage time (15 minutes for P1/P2)
3. **Multi-user or site-wide:** Any incident affecting more than one user or more than one device
4. **Any security indicator:** Phishing confirmed or suspected, malware detected, account compromise suspected, data accessed without authorisation, unusual network traffic
5. **Account re-enablement:** An account is disabled (not locked) and the user requests re-enablement - this requires manager approval and L2 verification
6. **Physical hardware:** Any issue requiring hardware replacement, physical repair, or on-site server work
7. **Cloud platform issue:** Azure Resource Health shows platform-initiated unavailability - not a config issue, not an L1 fix
8. **Change required:** Resolving the issue requires modifying a firewall rule, GPO, DNS record, Azure policy, or any infrastructure component

**When in doubt: escalate.** Holding a P1 at L1 trying to solve it independently is the
single biggest mistake an L1 engineer can make. Escalation is not failure - it is the
correct ITIL 4 response to an incident that exceeds L1 scope.

---

## L2 Escalation Handoff Template

Copy this template into every ticket being escalated. Do not escalate without filling
every field. An incomplete handoff is the most common cause of wasted L2 time.

```
ESCALATION HANDOFF
══════════════════════════════════════════════════
TICKET ID    : [INC-YYYYMMDD-XXXX]
PRIORITY     : [P1 / P2 / P3 / P4]
──────────────────────────────────────────────────
CALLER       : [Full name]
DEPARTMENT   : [Department]
CONTACT      : [Phone extension or mobile]
ASSET        : [Computer name / server name / system]
──────────────────────────────────────────────────
ISSUE        : [One clear sentence describing the symptom as reported by the caller]
──────────────────────────────────────────────────
TIMELINE:
  [HH:MM] Ticket logged
  [HH:MM] L1 triage started
  [HH:MM] [Step 1 taken] → [Result]
  [HH:MM] [Step 2 taken] → [Result]
  [HH:MM] [Step 3 taken] → [Result]
──────────────────────────────────────────────────
CURRENT STATE:
  [Describe exactly what is happening right now —
   not what happened when first reported]
──────────────────────────────────────────────────
REASON FOR ESCALATION:
  [Specific reason why this cannot be resolved at L1]
──────────────────────────────────────────────────
BUSINESS IMPACT:
  [What the user or team cannot do right now because of this issue]
══════════════════════════════════════════════════
```

---

## Ticket Closure Checklist

Before closing any ticket as resolved, confirm all of the following:

- [ ] User confirmed that the issue is resolved (do not close without confirmation)
- [ ] Steps taken are documented in the ticket in chronological order with timestamps
- [ ] Resolution is documented (not just "fixed" - what specifically was done)
- [ ] If escalated: L2 resolution notes are present in the ticket
- [ ] If a problem or change was identified: appropriate records have been raised and linked
- [ ] If security-related: security team sign-off is recorded in the ticket

---

## Common Ticket Types with Priority Guide

| Ticket Type | Typical Priority | Notes |
|-------------|-----------------|-------|
| Single user cannot log in | P3 | P2 if the user is a C-suite executive or critical operations role |
| Multiple users cannot log in | P1 | Potential domain or authentication system failure |
| Single user no internet | P2 | P1 if affects a team or site |
| Site-wide internet outage | P1 | Immediate escalation - do not triage individually |
| Email not working (single user) | P2 | P1 if affects multiple users or executives |
| Printer issue (single user) | P3 | P2 if the printer is shared by a team with time-sensitive work |
| Phishing email - not clicked | P2 | P1 if clicked or credentials entered |
| Phishing email - credentials entered | P1 | Disable account immediately, phone call to L2 Security |
| Malware detected - quarantined | P2 | P1 if active execution confirmed or lateral movement detected |
| Azure VM down | P2 | P1 if the VM is a production service affecting users |
| Disk space alert | P3 | P1 if disk is full and causing service failure |
| Password reset | P3 | P2 if the user is a critical role being blocked from time-sensitive work |
