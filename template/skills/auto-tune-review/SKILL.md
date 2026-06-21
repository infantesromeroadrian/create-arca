---
name: auto-tune-review
description: Prepare HITL context for reviewing an agent that crossed the @code-critic rejection threshold. Reads critic_rejections.json + recent session transcripts, extracts the last N rejection patterns mentioning the agent, and emits a structured handoff (counter, days pending, recent rejections, prompt path) ready to paste into @prompt-engineer context. Pure read-only — does NOT mutate state, does NOT auto-edit prompts. Activate when ⟦ user_name ⟧ says /auto-tune-review <agent-name>, revisa el agent X que está pending, prepárame contexto para auto-tune, or after the auto-tune-aging-detector hook surfaces a [AUTO-TUNE WARN] or [AUTO-TUNE CRITICAL] line.
when_to_use: when an agent is in auto_tune_pending state (banner [AUTO-TUNE WARN/CRITICAL] visible) and ⟦ user_name ⟧ wants to close the loop by invoking @prompt-engineer with structured context. NOT for ad-hoc agent prompt edits without prior code-critic rejections, NOT for first-time prompt drafting, NOT to inspect rejections of agents that are NOT in auto_tune_pending.
argument-hint: '<agent-name> [--limit=N] [--json] [--include-resolved]'
disable-model-invocation: false
user-invocable: true
allowed-tools: Bash, Read
model: sonnet
effort: low
---

# /auto-tune-review — HITL handoff for code-critic-rejected agents

Prepares the context an operator needs to invoke `@prompt-engineer` on an agent that has accumulated `@code-critic` rejections. Implements ADR-041 §3 (review skill).

## When to use

- The session-start banner shows `[AUTO-TUNE WARN]` or `[AUTO-TUNE CRITICAL]` for an agent.
- ⟦ user_name ⟧ wants to close the auto-tune loop manually for a specific agent.
- A retrospective wants to know "what was wrong with `@code-critic` over the last week".

## When NOT to use

- The agent is not in `auto_tune_pending` (the rejection counter is below 3 and there is no flag to close).
- ⟦ user_name ⟧ wants to edit a brand-new agent prompt — that is a `@prompt-engineer` from-scratch task, not a review.
- The state file `~/.claude/state/critic_rejections.json` does not exist (the tracker has not run yet).

## Inputs

| Flag | Default | Effect |
|---|---|---|
| `<agent-name>` | required | The agent to review. Must be in `auto_tune_pending` unless `--include-resolved` is set. |
| `--limit=N` | `5` | Number of recent rejection examples to pull from session transcripts. |
| `--json` | off | Machine-readable output. Default is plain human-readable. |
| `--include-resolved` | off | Allow review of an agent that is NOT currently flagged (useful for retrospectives). |

## Output (default plain)

```
=== Auto-tune review: @<agent> ===
  rejections:    28
  pending_since: 2026-04-15T12:00:00Z (25 days)
  severity:      CRITICAL (>= 14d, 2× SLA)
  prompt path:   agents/<agent>.md

Recent rejection patterns (last 5):
  [2026-05-08] session abc1234 — "code-critic BLOQUEANTE: …"
  [2026-05-06] session def5678 — "no aprueba el output de @<agent> porque …"
  …

Next step (HITL):
  Paste the above into @prompt-engineer context. ⟦ user_name ⟧ decides the edit;
  the existing reset-on-hash-change in critic-feedback-tracker.sh clears
  the flag automatically when agents/<agent>.md changes.
```

## Output (--json)

```json
{
  "agent": "<agent>",
  "rejections": 28,
  "pending_since": "2026-04-15T12:00:00Z",
  "days_pending": 25,
  "severity": "CRITICAL",
  "prompt_path": "agents/<agent>.md",
  "recent_rejections": [
    {"date": "2026-05-08", "session": "abc1234", "snippet": "…"},
    …
  ]
}
```

## Algorithm

1. Validate `<agent-name>` exists as `agents/<name>.md`.
2. Load `~/.claude/state/critic_rejections.json`. If the agent is not in `auto_tune_pending` and `--include-resolved` is not set, exit 1 with an explanatory message.
3. Read counter + `pending_since` for the agent. Compute days pending and severity (per ADR-041 SLA tiers).
4. Scan up to the most recent 20 session transcripts under `~/.claude/projects/<project-slug>/*.jsonl`. For each, grep for lines mentioning the agent name AND a rejection pattern (`BLOQUEANTE`, `rechazado`, `rejected`, `blocked`, `no aprueba`).
5. Extract up to `--limit` examples, each with date, session UUID, and a 200-char snippet around the match.
6. Emit plain or JSON output.
7. Exit 0.

## Determinism

Pure read-only. Same state file + same transcripts → same output. Does not call the network, does not invoke an LLM, does not edit any prompt. Stats are not persisted (this is a read-only consumer).

## Snippet format (v1 known limitation)

Recent rejection snippets are raw JSONL record lines from the transcript file, truncated to 200 chars. They are intentionally not pretty-printed because doing so reliably requires parsing each record as JSON and extracting `message.content[].text`, which adds parsing complexity not justified for v1. The operator who wants the full context opens the transcript at `~/.claude/projects/<slug>/<session-uuid>.jsonl` line N (the snippet starts with `N:`) — a follow-up improvement is tracked but not blocking.

## Failure modes

- State file missing → exit 1, message on stderr.
- Agent not in pending → exit 1 unless `--include-resolved`.
- No matching rejection patterns in recent transcripts → output still emitted, `recent_rejections` is empty, exit 0 (the operator may infer the agent was edited but the flag was not cleared, or the rejections happened in older transcripts than we scan).
- jq missing → exit 1 (jq is the JSON shaper).

## Composition

- Composes with ADR-041 (the SLA + state schema this skill consumes).
- Composes with the existing `hooks/critic-feedback-tracker.sh` — same state file, opposite end of the loop.
- Composes with `@prompt-engineer` — the operator pastes this output as context.

## Examples

```bash
# Default — review of code-critic with last 5 rejection snippets
/auto-tune-review code-critic

# More context for a deep dive
/auto-tune-review token-optimizer --limit=10

# JSON for programmatic ingestion
/auto-tune-review git-master --json

# Retrospective on an already-resolved agent
/auto-tune-review tester --include-resolved --limit=3
```
