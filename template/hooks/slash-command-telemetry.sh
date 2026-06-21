#!/usr/bin/env bash
# ARCA — Slash command telemetry recorder (Task #52, Lopopolo Prio 1)
#
# Captures `/<name>` slash command invocations to skill-telemetry.jsonl so
# /skill-effectiveness aggregates over the full surface of skill usage, not
# just the subset invoked via the native `Skill` tool.
#
# Gap closed:
#   Before this hook, telemetry only fired on PostToolUse:Skill — invocations
#   that go through the model-side Skill tool. The majority of skills are
#   invoked by the user typing `/<name>` directly, which the runtime expands
#   into the skill body inline without ever surfacing a Skill tool call.
#   That meant 97 of 100 catalog skills had zero recorded events in 5 days
#   even though ⟦ user_name ⟧ was actively using them. Task #52 audit surfaced the
#   gap; this hook fixes it.
#
# Source marker:
#   Events emitted by this hook carry `source: "slash-command"` so the
#   downstream aggregator can split coverage by invocation channel
#   (Skill-tool vs slash-command) and compute true skill-level usage.
#
# Schema (one JSON object per line, same JSONL file as skill-telemetry.sh):
#   {
#     "ts":      "<ISO-8601 timestamp>",
#     "skill":   "<command name without leading slash>",
#     "agent":   "main",
#     "session": "<sanitized session id>",
#     "outcome": "unknown",
#     "source":  "slash-command"
#   }
#
# Outcome is always "unknown" — UserPromptSubmit fires BEFORE execution, so
# we cannot know success/fail at this point. The aggregator must correlate
# subsequent tool events within a window (ARCA-DEBT-004, same gap as
# skill-telemetry.sh v2 outcome upgrade).
#
# DESIGN CONSTRAINTS
#   - jq required. Fail-open if missing (exit 0).
#   - Append-only single >> redirect (fits under PIPE_BUF for race safety).
#   - Silent: exit 0 unconditionally so a malformed payload never breaks
#     the user's turn.
#   - No filter on built-in vs skill — the aggregator decides by checking
#     if `skills/<name>/` exists in the repo. Logging everything keeps the
#     hook stateless and the policy decision in one place.

set -uo pipefail

payload="$(cat -)"

if ! command -v jq >/dev/null 2>&1; then
    exit 0
fi

prompt=$(printf '%s' "${payload}" | jq -r '.prompt // empty' 2>/dev/null || echo "")

# Only fire on lines that start with `/` followed by an identifier and either
# whitespace or end-of-string. Anchored regex avoids capturing mid-message
# mentions of slash-paths or URLs.
[[ "${prompt}" =~ ^/[a-z][a-z0-9_-]*([[:space:]]|$) ]] || exit 0

# Extract first token after the leading slash.
skill_name=$(printf '%s' "${prompt}" | sed -E 's|^/([a-z][a-z0-9_-]*).*|\1|')

# Sanity bound on name length (paranoid — defensive against regex edge cases).
skill_name="${skill_name:0:64}"

[[ -n "${skill_name}" ]] || exit 0

session=$(printf '%s' "${payload}" | jq -r '.session_id // empty' 2>/dev/null || echo "")
session="${session:0:36}"

ts="$(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S%z')"

jsonl="${HOME}/.claude/state/skill-telemetry.jsonl"

# Writability gate — bash evaluates `>>` before any trailing 2>/dev/null,
# so a read-only state dir would leak Permission denied to stderr (which
# pollutes the model's view of the prompt). Same pattern as
# git-commit-validator-stats.sh.
state_dir="$(dirname "${jsonl}")"
mkdir -p "${state_dir}" 2>/dev/null || exit 0
[[ -w "${state_dir}" ]] || exit 0
if [[ -e "${jsonl}" && ! -w "${jsonl}" ]]; then
    exit 0
fi

jq -nc \
    --arg ts "${ts}" \
    --arg skill "${skill_name}" \
    --arg session "${session}" \
    '{
        ts: $ts,
        skill: $skill,
        agent: "main",
        session: $session,
        outcome: "unknown",
        source: "slash-command"
    }' >> "${jsonl}" 2>/dev/null

exit 0
