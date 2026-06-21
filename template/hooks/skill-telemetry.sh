#!/bin/bash
# ARCA — Skill telemetry recorder (Hermes-3, Idea 3) — PostToolUse:Skill
#
# Appends one JSONL line per Skill invocation to
# ~/.claude/state/skill-telemetry.jsonl. The slash command
# /skill-effectiveness aggregates the file weekly and flags skills
# below a configurable success rate as CANDIDATES for manual review by
# ⟦ user_name ⟧. NEVER auto-rewrites — the rewrite path requires ⟦ user_name ⟧
# sign-off and the normal @prompt-engineer + @code-critic gates.
#
# Schema (one JSON object per line):
#   {
#     "ts":      "<ISO-8601 timestamp>",
#     "skill":   "<skill name>",
#     "agent":   "<calling agent or 'main'>",
#     "session": "<session id, sanitized>",
#     "outcome": "success" | "fail" | "unknown"
#   }
#
# OUTCOME PROXY — v1 (this implementation)
#   - tool_response.is_error == true   -> fail
#   - tool_response.error  truthy      -> fail
#   - tool_response.success == false   -> fail
#   - tool_response present, no error  -> success
#   - tool_response missing / empty    -> unknown
#
# OUTCOME PROXY — v2 (FUTURE, ARCA-DEBT-004, NOT in this hook)
#   A more accurate signal would correlate the skill invocation with
#   the 60 seconds of activity that follow it: an Edit/Write/MultiEdit
#   that gets reverted, a forced-justification block, or a code-critic
#   rejection within the window would mark the skill as fail even if
#   the immediate tool_response was clean. v2 needs a separate
#   correlator process (e.g. a tail+watch on the JSONL plus the
#   PostToolUse stream of subsequent tools), which is out of scope for
#   v1. ARCA-DEBT-004 tracks the upgrade.
#
# DESIGN CONSTRAINTS
#   - Bash, no Python (cold-start budget bounded; hook fires on every
#     PostToolUse:Skill).
#   - Silent: exit 0 unconditionally so a malformed payload never
#     breaks the user's session. Stats helper failures swallowed.
#   - Append-only with a single >> redirect; no rewrite-in-place. The
#     append fits well under PIPE_BUF on Linux (4096 bytes), so
#     concurrent writers do not interleave bytes within a single line.
#   - jq required. If jq is absent we still exit 0 — fail-open beats
#     poisoning the user's hook chain with a missing dep.
#   - Single jq pass for field extraction + outcome decision. Folding
#     the five jq calls of an earlier draft drops latency from ~36 ms
#     (cold-start dominated) to single-digit ms.
#
# TEST OVERRIDES
#   ARCA_SKILL_TELEMETRY_FILE       — redirect JSONL output (used by tests).
#   ARCA_SKILL_TELEMETRY_STATS_FILE — redirect stats counter file.

set -uo pipefail
umask 077

INPUT=$(cat 2>/dev/null || echo '{}')

command -v jq >/dev/null 2>&1 || exit 0

TS=$(date -Iseconds)
JSONL_FILE="${ARCA_SKILL_TELEMETRY_FILE:-${HOME}/.claude/state/skill-telemetry.jsonl}"
mkdir -p "$(dirname "$JSONL_FILE")" 2>/dev/null || exit 0

# Single jq pass: gate on tool_name, extract skill/agent/session, decide
# outcome v1, build the JSONL record. The inner script emits `empty`
# (no output) for any payload that is not a Skill or has no skill name,
# which short-circuits the writer below.
#
# Sanitization rules applied inside jq:
#   - Skill name and agent name: tostring, drop ASCII control bytes
#     via the POSIX [[:cntrl:]] class, cap at 64 bytes. Keeps the JSONL
#     one-line-per-record invariant intact even on hostile payloads.
#   - Session id: control-byte strip is implicit in the next gsub, then
#     whitelist [A-Za-z0-9_-] and cap at 64 bytes. UUID and epoch shapes
#     both round-trip without loss.
LINE=$(printf '%s' "$INPUT" | jq -c --arg ts "$TS" '
    def clean: tostring | gsub("[[:cntrl:]]"; "") | .[0:64];
    def cleansession: tostring | gsub("[^A-Za-z0-9_-]"; "") | .[0:64];

    if (.tool_name // "") != "Skill" then empty
    else
        ((.tool_input.skill_name // .tool_input.skill // .tool_input.name // "") | clean) as $skill
        | if $skill == "" then empty
          else
            ((.tool_input.calling_agent // .calling_agent // .agent // "main") | clean) as $agent_raw
            | (if $agent_raw == "" then "main" else $agent_raw end) as $agent
            | ((.session_id // "") | cleansession) as $session_raw
            | (if $session_raw == "" then "unknown" else $session_raw end) as $session
            | (.tool_response // null) as $resp
            # Outcome decision. has() is preferred over `// null` for the
            # success flag: jq returns null for both an absent key and an
            # explicit `false` value, so the // null pattern would silently
            # treat `success: false` as "key missing" and miscount the
            # outcome as success.
            | (if $resp == null then "unknown"
               elif ($resp | type) == "object" and ($resp | length) == 0 then "unknown"
               elif (($resp.is_error // false) == true) then "fail"
               elif (($resp.error // null) != null
                     and (($resp.error | type) != "string"
                          or ($resp.error | length) > 0)) then "fail"
               elif ($resp | has("success")) and $resp.success == false then "fail"
               else "success" end) as $outcome
            | {ts:$ts, skill:$skill, agent:$agent, session:$session, outcome:$outcome}
          end
    end
' 2>/dev/null)

[[ -z "$LINE" ]] && exit 0

# Single >> append. jq -c emits one line with no embedded newline; the
# write fits well under PIPE_BUF (4 KiB on Linux), so concurrent hooks
# cannot interleave bytes within a record.
printf '%s\n' "$LINE" >> "$JSONL_FILE" 2>/dev/null || exit 0

# Stats helper: bump total_invocations. Sibling races accepted (see
# ARCA-DEBT-001 5-way comment in skill-telemetry-stats.sh).
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-${PWD}}"
STATS_HELPER="${PROJECT_DIR}/hooks/lib/skill-telemetry-stats.sh"
[[ -x "$STATS_HELPER" ]] && bash "$STATS_HELPER" total_invocations 2>/dev/null || true

exit 0
