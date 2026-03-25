# ITIL 4 Ticket Workflow — L1 Help Desk Reference

## Ticket Priority Matrix

| Priority | Definition | Response SLA | Resolution SLA |
|----------|------------|-------------|----------------|
| P1 — Critical | Service completely down. Security incident. Data loss risk. | 15 minutes | 4 hours |
| P2 — High | Major degradation. Multiple users affected. | 1 hour | 8 hours |
| P3 — Medium | Single user affected. Workaround available. | 4 hours | 24 hours |
| P4 — Low | Cosmetic issue. Non-urgent request. | 8 hours | 72 hours |

## ITIL 4 Incident vs Problem vs Change

| Type | Definition | L1 Action |
|------|------------|-----------|
| **Incident** | Unplanned interruption to a service | Restore service FAST. Log, triage, escalate if needed. |
| **Problem** | Root cause of one or more incidents | Raise Problem ticket. Assign to L2/L3. Document workarounds. |
| **Change** | Planned modification to infrastructure | Log RFC. Follow change calendar. Never implement unplanned. |

## L1 Escalation Criteria

Always escalate to L2 if:
- Issue is not resolved within the P-level SLA window
- Root cause cannot be identified at L1
- Multiple users are affected
- Any security indicator is present (phishing, malware, data leak)
- Account requires re-enabling (not just unlocking)
- Physical hardware replacement is needed

## Ticket Documentation Standard

Every ticket must include before closing or escalating:
1. Exact symptoms as described by caller
2. Steps taken (in order)
3. Result of each step
4. Current state of the issue
5. Escalation reason (if escalating)