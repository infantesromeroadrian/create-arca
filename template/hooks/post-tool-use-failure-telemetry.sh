#!/bin/bash
set -euo pipefail

# PostToolUseFailure hook (matcher: .*) — closes ARCA's gate-integrity blind spot.
# Adopted by ADR-094 (2026-06-06).
#
# WHY this exists:
#   PostToolUse does NOT fire when a tool errors — a separate
#   PostToolUseFailure event does (Claude Code CLI 2.1.167). ARCA's gate
#   chain (math-critic-gate-enforcer.sh, code-critic-gate-enforcer.sh,
#   dynamic-orchestration-gate-enforcer.sh) runs on PostToolUse:Agent and is
#   therefore BLIND to a subagent that crashed instead of returning a verdict.
#   A crashed @code-critic invocation is currently indistinguishable from one
#   that was never invoked — which can silently defeat a blocking gate
#   (pecado mortal #1). This hook fires on failure and records it so the
#   crash is no longer invisible.
#
# WHAT this hook does:
#   Reads the PostToolUseFailure JSON on stdin, extracts tool_name, error,
#   subagent_type (when the failed tool was an Agent), session, and duration,
#   and appends exactly one event of type="tool_failure" to
#   ~/.claude/telemetry.jsonl. The event sits alongside the existing
#   "agent_invocation" / "tool_use" events; downstream analyzers filter by
#   type, so it does not double-count.
#
# INVARIANTS:
#   - ADVISORY ONLY — this hook CANNOT block. Exit 0 on every path. A
#     telemetry recorder must never break the flow it observes.
#   - Defensive parse: every field uses jq `// empty` with a multi-shape
#     probe (the payload schema is version-sensitive — same discipline as
#     agent-invocation-logger.sh). An all-empty parse (malformed/empty
#     stdin) logs nothing and exits 0 — see the phantom-event guard below.
#   - The error field is masked through lib/secrets-mask.sh before being
#     written — an error string can echo back a leaked token or header.
#   - Writes at most one JSONL line per failure event.
#
# DEBUG:
#   Export ARCA_HOOK_DEBUG=1 to tee raw stdin to
#   /tmp/arca-failure-hook-inspect-<session>.json for schema inspection.
#   Never enable in CI — stdin may contain user data.

INPUT=$(cat)
LOG_FILE="${HOME}/.claude/telemetry.jsonl"

# Optional debug dump (off by default, opt-in via env).
if [[ "${ARCA_HOOK_DEBUG:-0}" == "1" ]]; then
  DBG_SESSION=$(printf '%s' "$INPUT" | jq -r '.session_id // "nosession"' 2>/dev/null || echo "nosession")
  printf '%s' "$INPUT" > "/tmp/arca-failure-hook-inspect-${DBG_SESSION}.json" 2>/dev/null || true
fi

# Short-circuit if jq is missing — we cannot parse without it. Exit 0 so a
# machine without jq never breaks the (already failed) tool flow further.
command -v jq >/dev/null 2>&1 || exit 0

{
  TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || echo "")

  # Error text lives under different keys across versions. Probe in priority
  # order: tool_response.error (structured), then a top-level .error.
  ERROR=$(printf '%s' "$INPUT" | jq -r '
    (.tool_response.error
     // .error
     // .tool_response.message
     // empty)' 2>/dev/null || echo "")

  # subagent_type is only present when the failed tool was an Agent/Task call.
  SUBAGENT=$(printf '%s' "$INPUT" | jq -r '.tool_input.subagent_type // empty' 2>/dev/null || echo "")

  SESSION=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || echo "")

  # Phantom-event guard: malformed/empty stdin leaves every field empty.
  # Logging an empty tool_failure line would inflate the very metric this
  # hook exists to protect, so exit 0 without writing.
  if [[ -z "$TOOL_NAME" && -z "$ERROR" && -z "$SESSION" ]]; then
    exit 0
  fi

  # Duration: try top-level then the nested response shape, default 0.
  DURATION=$(printf '%s' "$INPUT" | jq -r '(.duration_ms // .tool_response.duration_ms // 0)' 2>/dev/null || echo "0")
  # Coerce to a plain integer: a non-numeric duration would make the
  # --argjson below emit a jq parse error to stderr. Default to 0.
  [[ "$DURATION" =~ ^[0-9]+$ ]] || DURATION=0

  # Mask credentials in the error text before logging — an error message is
  # tool-derived text that may echo a leaked token, Authorization header, or
  # request body. Same rationale as agent-invocation-logger.sh masks
  # the operator-supplied description.
  # shellcheck source=lib/secrets-mask.sh
  if [[ -f "${HOME}/.claude/hooks/lib/secrets-mask.sh" ]]; then
    source "${HOME}/.claude/hooks/lib/secrets-mask.sh"
    if command -v mask_secrets >/dev/null 2>&1; then
      ERROR=$(mask_secrets "$ERROR")
    fi
  fi

  TS=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

  # jq -nc builds the line so all string fields are JSON-escaped — an error
  # message containing quotes/newlines cannot corrupt the JSONL.
  jq -nc \
    --arg ts "$TS" \
    --arg type "tool_failure" \
    --arg tool_name "$TOOL_NAME" \
    --arg subagent_type "$SUBAGENT" \
    --arg error "$ERROR" \
    --arg session "$SESSION" \
    --argjson duration_ms "${DURATION:-0}" \
    '{ts:$ts,
      type:$type,
      tool_name:$tool_name,
      subagent_type:$subagent_type,
      error:$error,
      session:$session,
      duration_ms:$duration_ms}' \
    >> "$LOG_FILE"
} || true

# Rotation delegated to the shared flock-guarded helper, identical policy to
# agent-invocation-logger.sh — concurrent producers cannot race the trim.
# Triggers at >2*5000 lines OR >30MB. Best-effort, never fatal.
bash "${HOME}/.claude/hooks/lib/telemetry-rotate.sh" "$LOG_FILE" 5000 30 2>/dev/null || true

exit 0
