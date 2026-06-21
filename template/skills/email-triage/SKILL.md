---
name: email-triage
description: Batch inbox triage for ⟦ user_name ⟧. Reads last N unread emails via gmail MCP, classifies each into action buckets (reply_now, reply_later, read_only, delete_candidate, archive, forward), produces an executive summary and a batch-action plan. Integrates with Track B Feature #1 (ambient-monitor cooldown) to avoid re-notifying already-triaged signals.
paths:
  - "**/inbox/**"
  - "**/email/**"
effort: medium
---

# EMAIL TRIAGE — JARVIS-style inbox processing

Nobody should ever read their inbox line by line. That is the job of the
assistant. ARCA's email-triage skill exists to turn a raw inbox into a
5-minute review: urgent items flagged, bulk actions proposed, everything
else queued for later.

---

## WHEN TO INVOKE

- User says: "triage mi bandeja", "procesa los emails", "qué hay nuevo en el correo".
- Start of day (optional): as part of `/morning-briefing` §Ambient Highlights expansion.
- After a long session away from email (>8h without inbox review).

## WHEN NOT TO INVOKE

- User only asked to READ a specific email. Use gmail MCP directly, not this skill.
- If ambient-monitor already flagged something HIGH in last 30 minutes, surface that first; triage the rest after.

---

## INPUTS

| Source | Provider |
|---|---|
| Unread messages | `gmail` MCP (`search_threads` with `q="is:unread"`) or `gmail-google` fallback |
| Priority senders list | `~/.claude/ambient-config.json` → `priority_senders` |
| High-urgency keywords | `~/.claude/ambient-config.json` → `keywords_high` |
| Ambient cooldown state | `~/.claude/ambient-state.json` (to skip already-notified) |

---

## ACTION BUCKETS

Every message goes into EXACTLY ONE bucket. No compound assignments.

| Bucket | Definition | Default action |
|---|---|---|
| `reply_now` | Sender is priority OR subject/body has `keywords_high`. Requires response within 4h. | Draft reply preview for ⟦ user_name ⟧'s approval |
| `reply_later` | Action required but not urgent (review, decision, feedback). | Queue for later, suggest response template |
| `read_only` | FYI / informational that ⟦ user_name ⟧ should KNOW but not RESPOND to | Summarize in 1 line |
| `delete_candidate` | Newsletter, marketing, unsubscribe-worthy | Group for bulk delete + suggest unsubscribe |
| `archive` | Useful context, no action, not FYI either (receipts, confirmations, notifications) | Auto-archive suggestion |
| `forward` | Not for ⟦ user_name ⟧ — wrong recipient, CC spam, or belongs to another person/team | Suggest forward target |

## CLASSIFICATION RULES (in order — first match wins)

1. **reply_now**: sender in priority_senders AND (subject/body has keyword_high OR thread has >2 messages already)
2. **reply_now**: subject/body contains priority keyword (urgent, deadline, asap, blocked, incident, prod down)
3. **forward**: ⟦ user_name ⟧ is in CC only AND first recipient in To: is someone else on the team
4. **delete_candidate**: sender domain in common newsletter providers (mailchimp, substack, beehiiv, convertkit, sendinblue, sendgrid) OR subject has `[newsletter]`, `[digest]`, `unsubscribe`
5. **archive**: automated receipts, booking confirmations, github notifications about OWN commits, 2FA codes already consumed
6. **reply_later**: sender is known contact, asks a question or mentions "feedback", "review", "thoughts", "decide"
7. **read_only**: everything else

---

## OUTPUT FORMAT

ALWAYS deliver in this order:

### 1. Summary header
```
Inbox triage — {date}
N unread · {high}high · {med}medium · {low}low
```

### 2. Action buckets (only show non-empty buckets)
```
## Reply now (N)
- [sender] subject line — reason tag
  suggested action: <verb> ...

## Reply later (N)
- [sender] subject — 1-line summary
  suggested template: ...

## Read only (N)
- [sender] subject — 1-line takeaway

## Delete candidates (N) — bulk action proposed
- List by sender (not individual emails)
- Propose: "Unsubscribe from N/M of these senders?"

## Archive (N)
- List grouped by type (receipts, github notifications, etc.)

## Forward (N)
- [sender] subject → suggested recipient
```

### 3. Batch actions (explicit consent required)
```
Proposed batch actions:
- [ ] Archive all receipts (N msgs)
- [ ] Delete all newsletters (N msgs)
- [ ] Mark read all github notifications on own commits (N msgs)

Reply "1,2,3" to execute or "none" to skip.
```

NEVER execute batch actions without explicit user confirmation. Draft replies stay as drafts, not sent.

---

## ANTI-PATTERNS

- Do not send any email without explicit user approval. Drafts only.
- Do not mark as read en masse without bucket-level confirmation.
- Do not archive anything from `priority_senders` even if it looks like a receipt — ⟦ user_name ⟧ may want to see it.
- Do not invent email content — if the body snippet is empty in the MCP response, say so rather than hallucinate.
- Do not classify a single message into multiple buckets — first match wins.
- Do not run more than once per hour automatically — this is user-triggered or per-session, not a background daemon.

---

## INTEGRATION WITH ARCA

- **Track B Feature #1 (ambient-monitor):** the ambient scanner may have already classified and notified individual emails in real time. email-triage is the BATCH review of everything accumulated since last triage. Deduplication: consult `~/.claude/ambient-state.json` cooldown map to skip subjects already surfaced in last 30 minutes.
- **Engram:** after triage, save a summary ("triaged N emails, X reply_now, Y archived") to Engram for later recall in morning briefings.
- **Obsidian:** optional — write the triage output to `/Projects/ARCA/InboxLog/{date}.md` if ⟦ user_name ⟧ wants persistent record.
- **Voice notification:** deprecated 2026-05-11 — `hooks/voice-notify.sh` was unwired for 17 days and removed (no NVIDIA_API_KEY configured). If voice surface returns, integration point would be a Stop hook or skill-side TTS call; out of scope until then.

---

## KILL SWITCH

If the gmail MCP is down or the inbox is too large (>200 unread), abort with a single line:
> Inbox has N unread. Too many for productive triage — review manually or narrow filter first.

Never try to process 500+ unread in one pass. Suggest splitting by date range or sender.
