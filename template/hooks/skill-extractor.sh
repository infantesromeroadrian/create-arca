#!/bin/bash
set -euo pipefail

# PostToolUse hook (matcher: Bash) — detects fix/debug patterns
# Logs to ~/.claude/telemetry.jsonl with type "skill_pattern"

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

[[ -z "$COMMAND" ]] && exit 0

# Only log fix/debug pattern commands
echo "$COMMAND" | grep -qiE '(fix|solve|debug|patch|workaround|sed -i|pip install)' || exit 0

# P0-H1 fix (audit 2026-05-16): mask credentials in command and response
# before writing to telemetry. Both fields are user-supplied free-text
# that may contain pasted tokens (AWS keys, GitHub PATs, JWT bearers).
# Shared library — same pattern as command_logger.sh + agent-invocation-logger.sh.
# shellcheck source=lib/secrets-mask.sh
if [[ -f "${HOME}/.claude/hooks/lib/secrets-mask.sh" ]]; then
  source "${HOME}/.claude/hooks/lib/secrets-mask.sh"
fi

{
  LOG_FILE="${HOME}/.claude/telemetry.jsonl"
  RESPONSE=$(echo "$INPUT" | jq -r '.tool_response // empty' 2>/dev/null | head -5)
  SESSION=$(echo "$INPUT" | jq -r '.session_id // ""')
  AGENT=$(echo "$INPUT" | jq -r '.agent_name // ""')
  TS=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

  if command -v mask_secrets >/dev/null 2>&1; then
    COMMAND=$(mask_secrets "$COMMAND")
    RESPONSE=$(mask_secrets "$RESPONSE")
  fi

  jq -nc \
    --arg ts "$TS" \
    --arg type "skill_pattern" \
    --arg command "$COMMAND" \
    --arg result "$RESPONSE" \
    --arg agent "$AGENT" \
    --arg session "$SESSION" \
    '{ts:$ts,type:$type,command:$command,result:$result,agent:$agent,session:$session}' \
    >> "$LOG_FILE"
} || true

exit 0
