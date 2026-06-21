#!/bin/bash
set -euo pipefail

# PostToolUse hook (matcher: Agent) — resolves ARCA's telemetry blind-spot.
#
# WHY this exists:
#   log-activity.sh (matcher: .*) writes every tool_use but cannot resolve
#   which *subagent* was invoked: Claude Code does not inject agent_name for
#   Task/Agent tool calls — the name lives in tool_input.subagent_type.
#   Consequence: scripts/telemetry-analyzer.py reports "0 agents invocados"
#   even when the pipeline is actively delegating.
#
# WHAT this hook does:
#   Reads the PostToolUse JSON on stdin, extracts subagent_type, duration,
#   token counts and success flag, and appends a dedicated event of
#   type="agent_invocation" to ~/.claude/telemetry.jsonl. This event is
#   disjoint from the generic tool_use event (analyzer must not double-count).
#
# INVARIANTS:
#   - Exit 0 on every path (silent failure) — telemetry must never break flow.
#   - Only fires when tool_name == "Agent" AND subagent_type is non-empty;
#     otherwise short-circuits with exit 0.
#   - Writes exactly one JSONL line per successful invocation.
#   - Schema is a strict superset of the existing tool_use schema so the
#     analyzer can ingest both shapes without branching.
#
# DEBUG:
#   To inspect the raw hook input schema in production, temporarily enable
#   the DEBUG_INSPECT guard by exporting ARCA_HOOK_DEBUG=1. The hook will
#   tee stdin to /tmp/arca-agent-hook-inspect-<session>.json. Never enable
#   in CI — stdin may contain user data.

# Whitelist of agents that do NOT require preflight (mirrors CLAUDE.md and
# delegation-preflight-enforcer.sh). Kept in sync by convention; a single
# source file is deferred as documented deb in docs/ARCA_COMPLIANCE.md.
PREFLIGHT_EXEMPT_AGENTS=(
    "git-master" "docs-writer" "cost-analyzer" "sensei"
    "token-optimizer" "skill-router" "prompt-engineer"
    "math-critic" "code-critic" "debt-detector" "model-evaluator"
    "arca-ambient-monitor"
    "general-purpose" "Explore" "Plan" "statusline-setup" "claude-code-guide"
)

is_preflight_exempt() {
    local name="$1"
    local a
    for a in "${PREFLIGHT_EXEMPT_AGENTS[@]}"; do
        [[ "$name" == "$a" ]] && return 0
    done
    return 1
}

INPUT=$(cat)
LOG_FILE="${HOME}/.claude/telemetry.jsonl"

# Optional debug dump (off by default, opt-in via env).
if [[ "${ARCA_HOOK_DEBUG:-0}" == "1" ]]; then
  DBG_SESSION=$(printf '%s' "$INPUT" | jq -r '.session_id // "nosession"' 2>/dev/null || echo "nosession")
  printf '%s' "$INPUT" > "/tmp/arca-agent-hook-inspect-${DBG_SESSION}.json" 2>/dev/null || true
fi

# Short-circuit if jq is missing — we cannot parse without it.
command -v jq >/dev/null 2>&1 || exit 0

TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || echo "")
[[ "$TOOL_NAME" != "Agent" ]] && exit 0

SUBAGENT=$(printf '%s' "$INPUT" | jq -r '.tool_input.subagent_type // empty' 2>/dev/null || echo "")
[[ -z "$SUBAGENT" ]] && exit 0

{
  DESCRIPTION=$(printf '%s' "$INPUT" | jq -r '.tool_input.description // ""' 2>/dev/null || echo "")
  SESSION=$(printf '%s' "$INPUT" | jq -r '.session_id // ""' 2>/dev/null || echo "")

  # P1-11 fix (audit 2026-05-15): mask credentials in description
  # before logging — same rationale as command_logger.sh. Description
  # is operator-supplied text and may contain pasted tokens.
  # shellcheck source=lib/secrets-mask.sh
  if [[ -f "${HOME}/.claude/hooks/lib/secrets-mask.sh" ]]; then
    source "${HOME}/.claude/hooks/lib/secrets-mask.sh"
    if command -v mask_secrets >/dev/null 2>&1; then
      DESCRIPTION=$(mask_secrets "$DESCRIPTION")
    fi
  fi

  # Token usage: Claude Code exposes several plausible shapes across versions.
  # Probe in priority order, coerce to integer, fallback to null if absent.
  TOKENS_IN=$(printf '%s' "$INPUT" | jq -r '
    (.tool_response.usage.input_tokens
     // .tool_response.totalTokens
     // .tokens_in
     // empty)
    | tostring' 2>/dev/null || echo "")
  TOKENS_OUT=$(printf '%s' "$INPUT" | jq -r '
    (.tool_response.usage.output_tokens
     // .tokens_out
     // empty)
    | tostring' 2>/dev/null || echo "")
  DURATION=$(printf '%s' "$INPUT" | jq -r '(.duration_ms // .tool_response.duration_ms // 0)' 2>/dev/null || echo "0")

  # Success: Claude Code marks failure via is_error or a non-zero exit field.
  IS_ERROR=$(printf '%s' "$INPUT" | jq -r '(.tool_response.is_error // false)' 2>/dev/null || echo "false")
  if [[ "$IS_ERROR" == "true" ]]; then
    SUCCESS="false"
  else
    SUCCESS="true"
  fi

  TS=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

  # Build JSON with proper null handling — token fields are null (not 0)
  # when the data simply was not provided by Claude Code, so downstream
  # aggregators can distinguish "zero" from "missing".
  TOKENS_IN_ARG="null"
  [[ -n "$TOKENS_IN" ]] && [[ "$TOKENS_IN" != "null" ]] && TOKENS_IN_ARG="$TOKENS_IN"
  TOKENS_OUT_ARG="null"
  [[ -n "$TOKENS_OUT" ]] && [[ "$TOKENS_OUT" != "null" ]] && TOKENS_OUT_ARG="$TOKENS_OUT"

  # ──────────────────────────────────────────────────────────────────────
  # Compliance telemetry — records whether the preflight checklist was met
  # for this invocation. Observability-only: this hook does NOT block.
  # The actual gate lives in delegation-preflight-enforcer.sh (PreToolUse).
  # ──────────────────────────────────────────────────────────────────────
  IS_UTILITY="false"
  if is_preflight_exempt "$SUBAGENT"; then
      IS_UTILITY="true"
  fi

  TOKEN_OPT_BEFORE="false"
  SKILL_ROUTER_BEFORE="false"
  if [[ -n "$SESSION" ]] && [[ -f "$LOG_FILE" ]]; then
      # Session-wide grep (same semantics as the preflight enforcer).
      # Use $LOG_FILE BEFORE appending the current event — the new event is
      # built below and flushed at end of block, so the file state here
      # reflects only prior invocations.
      if grep -F "\"session\":\"${SESSION}\"" "$LOG_FILE" 2>/dev/null \
          | grep -F '"agent":"token-optimizer"' >/dev/null 2>&1; then
          TOKEN_OPT_BEFORE="true"
      fi
      if grep -F "\"session\":\"${SESSION}\"" "$LOG_FILE" 2>/dev/null \
          | grep -F '"agent":"skill-router"' >/dev/null 2>&1; then
          SKILL_ROUTER_BEFORE="true"
      fi
  fi

  # Compliant if utility (exempt) OR both preflight agents present.
  if [[ "$IS_UTILITY" == "true" ]] || \
     ([[ "$TOKEN_OPT_BEFORE" == "true" ]] && [[ "$SKILL_ROUTER_BEFORE" == "true" ]]); then
      COMPLIANT="true"
  else
      COMPLIANT="false"
  fi

  jq -nc \
    --arg ts "$TS" \
    --arg type "agent_invocation" \
    --arg agent "$SUBAGENT" \
    --arg description "$DESCRIPTION" \
    --arg session "$SESSION" \
    --argjson tokens_in "$TOKENS_IN_ARG" \
    --argjson tokens_out "$TOKENS_OUT_ARG" \
    --argjson duration_ms "${DURATION:-0}" \
    --argjson success "$SUCCESS" \
    --argjson is_utility "$IS_UTILITY" \
    --argjson token_optimizer_before "$TOKEN_OPT_BEFORE" \
    --argjson skill_router_before "$SKILL_ROUTER_BEFORE" \
    --argjson compliant "$COMPLIANT" \
    '{ts:$ts,
      type:$type,
      agent:$agent,
      description:$description,
      session:$session,
      tokens_in:$tokens_in,
      tokens_out:$tokens_out,
      duration_ms:$duration_ms,
      success:$success,
      preflight_compliance:{
        is_utility:$is_utility,
        token_optimizer_before:$token_optimizer_before,
        skill_router_before:$skill_router_before,
        compliant:$compliant
      }}' \
    >> "$LOG_FILE"
} || true

# Rotation delegated to the shared helper — atomic via flock so concurrent
# producers (log-activity.sh, command_logger.sh) cannot race. Triggers at
# >10k lines OR >30MB. Matches the unified policy.
bash "${HOME}/.claude/hooks/lib/telemetry-rotate.sh" "$LOG_FILE" 5000 30 2>/dev/null || true

exit 0
