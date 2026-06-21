#!/bin/bash
set -euo pipefail

# PostToolUse hook (matcher: Bash) — logs executed commands to telemetry stream
# Merges into ~/.claude/telemetry.jsonl with type "bash_command"

INPUT=$(cat)
LOG_FILE="${HOME}/.claude/telemetry.jsonl"

# P1-11 fix (audit 2026-05-15): mask credentials in command BEFORE
# writing to telemetry.jsonl. Without this, `export AWS_KEY=AKIA...;
# aws s3 ls` would land in telemetry verbatim. The lib is shared with
# agent-invocation-logger.sh and mirrors post-tool-secrets-mask.sh.
# shellcheck source=lib/secrets-mask.sh
if [[ -f "${HOME}/.claude/hooks/lib/secrets-mask.sh" ]]; then
    source "${HOME}/.claude/hooks/lib/secrets-mask.sh"
fi

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || echo "")
[[ -z "$COMMAND" ]] && exit 0

# Apply masking if the helper loaded; degrade to raw if absent (telemetry
# never blocks tool execution — secrets in unmasked telemetry is still a
# softer failure than dropping the event).
if command -v mask_secrets >/dev/null 2>&1; then
    COMMAND=$(mask_secrets "$COMMAND")
fi

{
  SESSION=$(echo "$INPUT" | jq -r '.session_id // ""')
  AGENT=$(echo "$INPUT" | jq -r '.agent_name // ""')
  EXIT_CODE=$(echo "$INPUT" | jq -r '.tool_response.exitCode // 0' 2>/dev/null || echo "0")
  TS=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

  jq -nc \
    --arg ts "$TS" \
    --arg type "bash_command" \
    --arg command "$COMMAND" \
    --arg agent "$AGENT" \
    --arg session "$SESSION" \
    --argjson exit_code "${EXIT_CODE:-0}" \
    '{ts:$ts,type:$type,command:$command,agent:$agent,session:$session,exit_code:$exit_code}' \
    >> "$LOG_FILE"
} || true

# Rotation delegated to the shared helper — atomic via flock so concurrent
# producers (log-activity.sh, agent-invocation-logger.sh) cannot race.
# Triggers at >10k lines OR >30MB.
bash "${HOME}/.claude/hooks/lib/telemetry-rotate.sh" "$LOG_FILE" 5000 30 2>/dev/null || true

exit 0
