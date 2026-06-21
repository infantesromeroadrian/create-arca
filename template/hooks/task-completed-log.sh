#!/bin/bash
# ARCA — TaskCompleted event hook (Claude Code 2.1.84+ Agent Teams)
#
# Fires when a task in the Agent Team shared list transitions to
# completed. We log: which teammate closed it, duration, exit status.
# Without this hook there is no attribution — you cannot tell whether
# the Architect or the Adversary teammate carried the heavy lift in a
# /voting-review-team run.
#
# Stays silent and exit-0; never blocks. The blocking critic-gate
# enforcement lives elsewhere (code-critic-gate-enforcer.sh etc).

set -uo pipefail
umask 077

LOG="${HOME}/.claude/state/agent-teams-completed.log"
JSONL="${HOME}/.claude/state/agent_teams_telemetry.jsonl"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || true

# shellcheck source=lib/secrets-mask.sh
if [[ -f "${HOME}/.claude/hooks/lib/secrets-mask.sh" ]]; then
    source "${HOME}/.claude/hooks/lib/secrets-mask.sh"
fi

input="$(cat 2>/dev/null || true)"
ts="$(date -Iseconds)"

team="$(printf '%s' "$input" | jq -r '.team // .team_name // ""' 2>/dev/null)"
teammate="$(printf '%s' "$input" | jq -r '.teammate // .teammate_name // .completed_by // ""' 2>/dev/null)"
task_id="$(printf '%s' "$input" | jq -r '.task_id // .id // ""' 2>/dev/null)"
task_desc="$(printf '%s' "$input" | jq -r '.task_description // .description // .task // ""' 2>/dev/null | head -c 120 | tr '\n' ' ')"
duration_s="$(printf '%s' "$input" | jq -r '.duration_seconds // .duration_s // 0' 2>/dev/null)"
status="$(printf '%s' "$input" | jq -r '.status // .exit_status // "ok"' 2>/dev/null)"
session="$(printf '%s' "$input" | jq -r '.session_id // ""' 2>/dev/null)"

if command -v mask_secrets >/dev/null 2>&1; then
    task_desc="$(mask_secrets "$task_desc")"
fi

printf '%s | team=%s | by=%s | task=%s | dur_s=%s | status=%s | desc=%s\n' \
    "$ts" "${team:-?}" "${teammate:-?}" "${task_id:-?}" "${duration_s:-?}" "${status:-?}" "${task_desc:-?}" \
    >> "$LOG"

jq -c -n \
    --arg ts "$ts" \
    --arg event "TaskCompleted" \
    --arg team "${team:-}" \
    --arg teammate "${teammate:-}" \
    --arg task_id "${task_id:-}" \
    --arg task_desc "${task_desc:-}" \
    --arg duration_s "${duration_s:-0}" \
    --arg status "${status:-ok}" \
    --arg session "${session:-}" \
    '{ts: $ts, event: $event, team: $team, teammate: $teammate, task_id: $task_id, task_desc: $task_desc, duration_seconds: ($duration_s | tonumber? // 0), status: $status, session: $session}' \
    >> "$JSONL" 2>/dev/null || true

exit 0
