---
description: Friday garbage-collection ritual — consolidate ARCA harness debt signals (telemetry anomalies, auto-tune-pending agents, pool debt, critic rejection patterns, bypass aggregation) into briefings/friday-gc-YYYY-MM-DD.md. Inspired by Ryan Lopopolo (OpenAI) — "Friday GC day, categorically eliminate slop observed during the week" (AI Engineer 2026-04-17, Lopopolo Prio 4). Manual `/friday-gc` or scheduled Friday 5pm ⟦ timezone ⟧.
---

# Friday GC Day — ARCA harness debt consolidation

This command runs the Friday garbage-collection ritual. The goal is NOT to fix everything — it is to **make accumulated debt visible** so ⟦ user_name ⟧ (or a follow-up session) can choose what to attack first the following week.

Inspired by Ryan Lopopolo (OpenAI, AI Engineer London 2026-04-17, transcript ingested into the LLM Wiki at `~/Documents/Obsidian Vault/LLM-Wiki/youtube/harness-engineering-how-to-build-software-when-humans-steer-agents-execute-ryan-.md` — local-only path, NOT in this repo; cloud-routine sandboxes will not resolve it): "Every Friday my team takes one day to take every bit of slop we had observed over the course of the week and figure out ways to categorically eliminate it." ARCA-adapted: surface the signals, decide the actions, do NOT auto-execute fixes.

## Steps

1. **Skill telemetry anomalies** — Read `~/.claude/state/skill-telemetry.jsonl` and `~/.claude/state/skill-telemetry-stats.json`:
   - Total invocations this week vs total skills in catalog
   - Top 5 most-invoked skills (heavy users — investigate why)
   - Top 5 skills with 0 invocations in last 30 days (deprecation candidates)
   - Skills with `outcome: fail` ratio > 20% (calibration candidates)
   - Note: `source: "slash-command"` events have `outcome: "unknown"` by design (Task #52 — ARCA-DEBT-004 deferred correlator)

2. **Auto-tune-pending agents** — Read `~/.claude/state/critic_rejections.json`. The file's real shape is `{rejections: {agent: count}, auto_tune_pending: [agent, ...], pending_since: {agent: ISO8601}, prompt_hashes: {agent: sha256}}`. The producer is `hooks/critic-feedback-tracker.sh` (PostToolUse:Agent on rejection signals). Useful queries:

   ```bash
   # Top 10 agents by rejection count this cycle
   jq -r '.rejections | to_entries | sort_by(-.value) | .[0:10]
          | map("\(.key)=\(.value)") | .[]' ~/.claude/state/critic_rejections.json

   # Agents currently in auto_tune_pending state
   jq -r '.auto_tune_pending | join(", ")' ~/.claude/state/critic_rejections.json

   # Aging signal — days since each agent entered pending
   jq -r '.pending_since // {} | to_entries
          | map("\(.key): \(.value)") | .[]' ~/.claude/state/critic_rejections.json
   ```

   Surface each `auto_tune_pending` agent older than 7 days via `/auto-tune-review <agent-name>` for HITL action this week.

3. **Pool debt detected** — Search the repo for accumulated debt markers:
   - `grep -rn "TODO\|FIXME\|XXX\|HACK"` in `hooks/`, `agents/`, `skills/`, `scripts/` (exclude `tests/`, `docs/`, `briefings/`, `.github/`, `node_modules/`)
   - `grep -rn "ARCA-DEBT-[0-9]\+"` in same paths — accumulated deferred decisions
   - Sort by file age (oldest debt first surface)
   - Cap at the 15 oldest entries

4. **Critic rejection patterns** — Cross-reference `critic_rejections.json` (Step 2) with `~/.claude/state/skill-telemetry-resolved.jsonl` (ARCA-DEBT-004 correlator, Task #57). The resolved JSONL classifies skill invocations as `active` / `fail` / `abandoned`; correlating those `fail` events with rejection counts surfaces which agent prompts are aging most aggressively. There is NO standalone `critic-feedback.log` — earlier drafts of this command referenced one in error (caught by the smoke-test run on 2026-05-11). The real producer is `critic-feedback-tracker.sh` writing to `critic_rejections.json` only.

   Useful aggregate:
   ```bash
   # Cross-ref pending agents with their fail-rate from resolved telemetry
   jq -r '.auto_tune_pending | .[]' ~/.claude/state/critic_rejections.json \
     | while read -r agent; do
         fail_count=$(jq -r --arg a "$agent" 'select(.skill == $a and .resolved_outcome == "fail") | 1' \
                        ~/.claude/state/skill-telemetry-resolved.jsonl 2>/dev/null | wc -l | tr -d ' ')
         echo "$agent: $fail_count fails resolved"
       done
   ```

   Surface agents with high rejection counts AND high resolved-fail counts as priority refactor candidates.

5. **Bypass aggregation** — Read bypass audit logs in `~/.claude/state/`:
   - `mcp-parity-bypasses.log` — ADR-033 hook bypasses
   - `prompt-guard-bypasses.log` — Task #53 hook bypasses
   - `comprehension-gate-bypasses.log` — ADR-008 PR comprehension bypasses
   - Count bypasses per week, flag if growing trend (indicates either a hook needs tightening, or an environment requires accommodation)

6. **Stats files anomalies** — Inspect `~/.claude/state/*-stats.json`:
   - Buckets that hit 0 all week (instrumentation broken or feature unused)
   - Buckets growing exponentially (potential bug or abuse)
   - `git-commit-validator-stats.json` (Task #50) — ratio of `skip_substitution` + `skip_heredoc` vs `pass_conventional`. If skip > pass, operators leaning on the fail-safe (ARCA-DEBT-004 telemetry-driven decision point).

7. **Lopopolo signal check (instrumentation gap — surface as items to instrument)** — Three signals Lopopolo's talk recommends tracking weekly, but ARCA today lacks the instrumentation for them. This step exists to keep the gap visible until the instrumentation lands:
   - Token usage per agent invocation — NOT instrumented. Decide quarterly whether to add a PostToolUse:Agent hook recording token totals.
   - `/voting-review-team` invocations where the operator did not read the plan line-by-line — NOT instrumented. Slash-command-telemetry (Task #52) captures the invocation; correlating with "diff-comprehension gate not fired" would close the loop.
   - First-party harness drift: count custom hooks that arguably duplicate Claude Code primitives — manual review against the hook catalog. Hook coverage delta vs upstream releases tracked in `claude-config-audit`.
   For each missing signal, report "INSTRUMENTATION GAP — pending decision". Do NOT fabricate values. The visibility itself is the action.

8. **Output to briefings** — Write `briefings/friday-gc-YYYY-MM-DD.md` with:
   - Executive summary (3 lines): biggest signal, top action recommended, count of items registered
   - Section per signal source (steps 1-7 above)
   - "Recommended actions for next week" section — ranked by ROI (highest signal-to-effort first)
   - Frontmatter: `type: friday-gc-briefing` + `week: <ISO week>`

9. **Commit + push** — Same pattern as morning-briefing / guardian-audit:
   - `git add briefings/friday-gc-YYYY-MM-DD.md`
   - `git commit -m "docs(briefings): friday-gc <YYYY-MM-DD>"`
   - `git push origin main`

## When NOT to run

- Sprint emergencies — Friday GC adds visibility, doesn't help solve a P0 incident.
- Day-before-vacation — no point surfacing debt if nobody will see it for 2 weeks.
- Already-overwhelming pool — if pool debt count > 50 unresolved items, this ritual amplifies anxiety rather than reducing it. Triage existing pool first.

## Schedule

Manually via `/friday-gc` whenever the operator chooses. To automate via Anthropic Scheduled Triggers (claude.ai/code/routines):
- Frequency: weekly
- Day: Friday
- Time: 17:00 ⟦ timezone ⟧ (post-workday but pre-weekend)
- Output: same briefings/ location, push to main, surfaced in following Monday's `/morning-briefing`

## Output contract

Every Friday GC briefing MUST contain at minimum:
- `frontmatter: type: friday-gc-briefing, week: WW, generated_at: <ISO-8601>`
- `## Executive summary` section (3 lines)
- One section per step 1-7 (even if "no signals this week")
- `## Recommended actions for next week` ranked by ROI

If a section returns no signals, write `_No signals this week._` rather than omitting the section. Empty sections are intentional — they pin the contract and surface instrumentation gaps if a counter stays at zero unexpectedly.

## Failure modes

- **No telemetry data**: stats files don't exist or are empty. Surface this as the top signal of the week — instrumentation gap.
- **Engram CLI absent**: cannot search session history. Skip step 2 partial (auto-tune-pending agents) but still run steps 1, 3, 5, 6.
- **Git push fails**: commit locally, surface push failure in next morning briefing.

## References

- Lopopolo, R. (2026-04-17). Harness Engineering: How to Build Software When Humans Steer, Agents Execute. AI Engineer London. https://www.youtube.com/watch?v=am_oeAoUhew
- LLM-Wiki entry (local Obsidian Vault, NOT in this repo): `~/Documents/Obsidian Vault/LLM-Wiki/youtube/harness-engineering-how-to-build-software-when-humans-steer-agents-execute-ryan-.md`
- BettaTech complementary (local Obsidian Vault): `~/Documents/Obsidian Vault/LLM-Wiki/youtube/qu-es-esto-del-harness-engineering.md`
- Task #55 (this command) closes Lopopolo Prio 4.
