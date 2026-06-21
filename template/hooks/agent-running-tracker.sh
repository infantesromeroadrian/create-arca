#!/bin/bash
set -euo pipefail

# PreToolUse hook (matcher: Agent) — tracks live subagent invocations.
#
# WHY this exists:
#   Telemetry only logs agent_invocation at completion. The statusline cannot
#   show "1 agent running @ml-engineer" because the event does not exist yet.
#   This hook writes a marker file at PreToolUse so the statusline can read
#   live state. agent-running-cleanup.sh removes the marker at PostToolUse.
#
# INVARIANTS:
#   - Always exits 0 (silent failure) — hook must never block delegation.
#   - Marker file name: <session>-<epoch>-<rand>.json so PostToolUse cleanup
#     can pair them in FIFO order if multiple of the same agent run in
#     parallel (rare, but the orchestrator does fan-out occasionally).
#   - Schema is minimal: agent name, session, started_at, pid (best-effort).
#
# STALE MARKER POLICY:
#   If Claude Code crashes between Pre and Post, marker leaks. The statusline
#   filters out markers older than 30 min. A daily cleanup is not added here
#   because the volume is low and stale entries are visible in the running
#   count, prompting manual cleanup if needed.

STATE_DIR="${HOME}/.claude/state/running-agents"
mkdir -p "$STATE_DIR" 2>/dev/null || exit 0
umask 077

INPUT=$(cat)

command -v jq >/dev/null 2>&1 || exit 0

# P0-H1 fix (audit 2026-05-16): description is operator-supplied free-text;
# pasted credentials would otherwise land in marker JSON. Mask via shared
# lib before serialization.
# shellcheck source=lib/secrets-mask.sh
if [[ -f "${HOME}/.claude/hooks/lib/secrets-mask.sh" ]]; then
    source "${HOME}/.claude/hooks/lib/secrets-mask.sh"
fi

TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || echo "")
[[ "$TOOL_NAME" != "Agent" ]] && exit 0

SUBAGENT=$(printf '%s' "$INPUT" | jq -r '.tool_input.subagent_type // empty' 2>/dev/null || echo "")
[[ -z "$SUBAGENT" ]] && exit 0

SESSION=$(printf '%s' "$INPUT" | jq -r '.session_id // ""' 2>/dev/null || echo "")
[[ -z "$SESSION" ]] && exit 0

EPOCH=$(date +%s)
RAND=$(printf '%04x' $((RANDOM)))
MARKER="${STATE_DIR}/${SESSION}-${EPOCH}-${RAND}.json"

DESCRIPTION=$(printf '%s' "$INPUT" | jq -r '.tool_input.description // ""' 2>/dev/null || echo "")
if command -v mask_secrets >/dev/null 2>&1; then
    DESCRIPTION=$(mask_secrets "$DESCRIPTION")
fi
TS=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

jq -nc \
  --arg agent "$SUBAGENT" \
  --arg session "$SESSION" \
  --arg started_at "$TS" \
  --arg description "$DESCRIPTION" \
  --argjson epoch "$EPOCH" \
  '{agent:$agent,session:$session,started_at:$started_at,epoch:$epoch,description:$description}' \
  > "$MARKER" 2>/dev/null || true

exit 0
