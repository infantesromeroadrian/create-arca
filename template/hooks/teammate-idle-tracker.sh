#!/bin/bash
# ARCA — TeammateIdle event hook (Claude Code 2.1.84+ Agent Teams)
#
# Fires when a teammate inside an Agent Team finishes its turn and
# becomes idle (no pending task in the shared list). Without this hook
# you have ZERO visibility on dead-time: teammates can sit idle for
# minutes while the Lead waits. We log every idle event so the Guardian
# Audit can compute per-teammate idle ratio and detect stalled agents.
#
# Stays silent and exit-0; never blocks the team. The shared task list
# rescheduling is the Lead's responsibility — this hook only observes.

set -uo pipefail
umask 077

LOG="${HOME}/.claude/state/agent-teams-idle.log"
JSONL="${HOME}/.claude/state/agent_teams_telemetry.jsonl"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || true

# Source shared secrets masking (consistent with task-created-audit.sh).
# shellcheck source=lib/secrets-mask.sh
if [[ -f "${HOME}/.claude/hooks/lib/secrets-mask.sh" ]]; then
    source "${HOME}/.claude/hooks/lib/secrets-mask.sh"
fi

input="$(cat 2>/dev/null || true)"
ts="$(date -Iseconds)"

teammate="$(printf '%s' "$input" | jq -r '.teammate // .teammate_name // .agent_name // ""' 2>/dev/null)"
team="$(printf '%s' "$input" | jq -r '.team // .team_name // ""' 2>/dev/null)"
idle_seconds="$(printf '%s' "$input" | jq -r '.idle_seconds // .idle_ms // 0' 2>/dev/null)"
last_task="$(printf '%s' "$input" | jq -r '.last_task // .last_completed_task // ""' 2>/dev/null | head -c 80 | tr '\n' ' ')"
session="$(printf '%s' "$input" | jq -r '.session_id // ""' 2>/dev/null)"

if command -v mask_secrets >/dev/null 2>&1; then
    last_task="$(mask_secrets "$last_task")"
fi

# Human-readable log line (Guardian Audit greppable).
printf '%s | team=%s | teammate=%s | idle_s=%s | last_task=%s\n' \
    "$ts" "${team:-?}" "${teammate:-?}" "${idle_seconds:-?}" "${last_task:-?}" \
    >> "$LOG"

# Machine-readable JSONL (skill-effectiveness aggregation friendly).
jq -c -n \
    --arg ts "$ts" \
    --arg event "TeammateIdle" \
    --arg team "${team:-}" \
    --arg teammate "${teammate:-}" \
    --arg idle_seconds "${idle_seconds:-0}" \
    --arg last_task "${last_task:-}" \
    --arg session "${session:-}" \
    '{ts: $ts, event: $event, team: $team, teammate: $teammate, idle_seconds: ($idle_seconds | tonumber? // 0), last_task: $last_task, session: $session}' \
    >> "$JSONL" 2>/dev/null || true

exit 0
