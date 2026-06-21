#!/bin/bash
set -euo pipefail

# PostToolUse hook (matcher: .*) — structured JSON-lines telemetry
# Logs every tool invocation to ~/.claude/telemetry.jsonl

INPUT=$(cat)
LOG_FILE="${HOME}/.claude/telemetry.jsonl"

{
  TOOL=$(echo "$INPUT" | jq -r '.tool_name // "unknown"')
  SESSION=$(echo "$INPUT" | jq -r '.session_id // ""')
  # ADR-043: when tool_name == "Agent", Claude Code does NOT inject .agent_name;
  # the subagent slug lives in .tool_input.subagent_type. Prior to ADR-043 this
  # field was silently empty for every Agent invocation (215 historical rows).
  # The analyzer in scripts/telemetry-analyzer.py::analyze_agents() filters
  # (type=tool_use, tool=Agent) so populating `agent` here does NOT cause
  # double-counting against the dedicated agent_invocation stream.
  if [[ "$TOOL" == "Agent" ]]; then
    AGENT=$(echo "$INPUT" | jq -r '.tool_input.subagent_type // ""')
  else
    AGENT=$(echo "$INPUT" | jq -r '.agent_name // ""')
  fi
  TOKENS_IN=$(echo "$INPUT" | jq -r '.tokens_in // 0')
  TOKENS_OUT=$(echo "$INPUT" | jq -r '.tokens_out // 0')
  DURATION=$(echo "$INPUT" | jq -r '.duration_ms // 0')
  TS=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

  jq -nc \
    --arg ts "$TS" \
    --arg type "tool_use" \
    --arg tool "$TOOL" \
    --arg agent "$AGENT" \
    --arg session "$SESSION" \
    --arg phase "" \
    --argjson tokens_in "${TOKENS_IN:-0}" \
    --argjson tokens_out "${TOKENS_OUT:-0}" \
    --argjson duration_ms "${DURATION:-0}" \
    '{ts:$ts,type:$type,tool:$tool,agent:$agent,session:$session,phase:$phase,tokens_in:$tokens_in,tokens_out:$tokens_out,duration_ms:$duration_ms}' \
    >> "$LOG_FILE"
} || true

# Rotation delegated to the shared helper — keeps the trim atomic via flock
# so concurrent producers (command_logger.sh, agent-invocation-logger.sh)
# cannot race each other and drop events. Triggers at >10k lines OR >30MB.
bash "${HOME}/.claude/hooks/lib/telemetry-rotate.sh" "$LOG_FILE" 5000 30 2>/dev/null || true

exit 0
