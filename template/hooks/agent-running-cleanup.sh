#!/bin/bash
set -euo pipefail

# PostToolUse hook (matcher: Agent) — clears the marker written at PreToolUse.
#
# WHY this exists:
#   Pair with agent-running-tracker.sh. When Agent finishes, find the oldest
#   marker for this (session, agent) pair and remove it. FIFO discipline so
#   parallel invocations of the same agent are tracked correctly.
#
# INVARIANTS:
#   - Always exits 0 — telemetry consistency must never block downstream hooks.
#   - Removes exactly one marker per Agent completion: the oldest matching
#     (session, agent). If no marker found, exits silently — likely the
#     pre-hook did not run (race or hook not deployed yet).

STATE_DIR="${HOME}/.claude/state/running-agents"
[[ ! -d "$STATE_DIR" ]] && exit 0

INPUT=$(cat)

command -v jq >/dev/null 2>&1 || exit 0

TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || echo "")
[[ "$TOOL_NAME" != "Agent" ]] && exit 0

SUBAGENT=$(printf '%s' "$INPUT" | jq -r '.tool_input.subagent_type // empty' 2>/dev/null || echo "")
[[ -z "$SUBAGENT" ]] && exit 0

SESSION=$(printf '%s' "$INPUT" | jq -r '.session_id // ""' 2>/dev/null || echo "")
[[ -z "$SESSION" ]] && exit 0

# Find oldest marker for (session, agent) and remove it. Use mtime ordering;
# the embedded epoch in the filename matches mtime within the second.
oldest=""
for f in "${STATE_DIR}/${SESSION}-"*.json; do
  [[ -f "$f" ]] || continue
  agent_in_file=$(jq -r '.agent // ""' "$f" 2>/dev/null || echo "")
  [[ "$agent_in_file" != "$SUBAGENT" ]] && continue
  if [[ -z "$oldest" ]] || [[ "$f" -ot "$oldest" ]]; then
    oldest="$f"
  fi
done

[[ -n "$oldest" ]] && rm -f "$oldest" 2>/dev/null

exit 0
