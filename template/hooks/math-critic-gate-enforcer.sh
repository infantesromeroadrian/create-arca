#!/bin/bash
set -uo pipefail
umask 077

# PostToolUse hook (matcher: Agent) — HARD-BLOCK enforcer for the
# Mandatory Math-Critic Gate.
#
# Rule (CLAUDE.md > Mandatory Math-Critic Gate):
#   producer (ml-engineer | dl-engineer | ai-engineer)
#     -> @math-critic
#     -> @debt-detector
#     -> @code-critic
#
# When @code-critic is invoked on the same session AFTER one of the three
# producers WITHOUT @math-critic having been invoked between the producer
# and @code-critic, this hook emits the Claude Code PostToolUse hard-block
# JSON contract on stdout:
#
#   {"decision":"block","reason":"..."}
#
# Claude Code blocks the next model turn with that reason in the transcript.
# Reference: docs.claude.com/en/docs/claude-code/hooks (PostToolUse > top-level
# decision control: decision="block").
#
# NOTE on the matcher: Claude Code dispatches subagent invocations with
# tool_name="Agent" (NOT "Task"). Earlier versions of this hook matched
# "Task", which made the gate a permanent no-op.
#
# Hardening:
#   - SESSION_ID is sanitized to [A-Za-z0-9_-] (no dots, no slashes) and
#     truncated to 64 chars before being used as a path segment. Prevents
#     traversal via crafted session_id (e.g., "../../tmp/x").
#   - State log uses epoch-nanosecond timestamps (date +%s%N) so two events
#     emitted within the same wall-clock second can be ordered correctly.
#   - State log reads/writes for the gate decision are guarded with flock so
#     concurrent invocations cannot interleave.
#   - umask 077 ensures state files are not world-readable.
#   - All early-exit branches are exit 0 (silent) — only an actual gate
#     violation produces the JSON block decision.

INPUT=$(cat)

# jq is mandatory — without it we cannot parse the hook input safely.
command -v jq >/dev/null 2>&1 || exit 0

TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || echo "")
[[ "$TOOL_NAME" != "Agent" ]] && exit 0

SUBAGENT=$(printf '%s' "$INPUT" | jq -r '.tool_input.subagent_type // empty' 2>/dev/null || echo "")
SESSION_ID_RAW=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || echo "")
[[ -z "$SUBAGENT" || -z "$SESSION_ID_RAW" ]] && exit 0

# Sanitize session id — keep ONLY [A-Za-z0-9_-] (no dots: '.' enables './'
# and '..' traversal even when slashes are stripped). Cap length at 64 to
# bound state-file names and prevent absurd inputs from creating huge paths.
# If sanitization leaves nothing, short-circuit — we have no usable key.
SESSION_ID=$(printf '%s' "$SESSION_ID_RAW" | tr -cd 'A-Za-z0-9_-' | cut -c1-64)
[[ -z "$SESSION_ID" ]] && exit 0

# Allow tests to redirect state to an isolated tmpdir.
STATE_DIR="${ARCA_GATE_STATE_DIR:-${HOME}/.claude/state/math-critic-gate}"
mkdir -p "$STATE_DIR" 2>/dev/null || exit 0
SESSION_LOG="${STATE_DIR}/${SESSION_ID}.log"
LOCK_FILE="${SESSION_LOG}.lock"

# Epoch-nanoseconds for sub-second ordering. Format per line:
#   <NANOS> <TYPE> <DETAIL>
NANOS=$(date +%s%N)

# emit_block — write the JSON hard-block contract to stdout and exit 0.
# We must not exit 2 here: when Claude Code reads valid JSON on stdout it
# uses the decision field, and exit 0 keeps the contract clean.
emit_block() {
  local producer="$1"
  local reason
  reason=$(printf '[MATH-CRITIC-GATE] @code-critic invoked on @%s output without @math-critic in between. Required chain: producer -> @math-critic -> @debt-detector -> @code-critic. See CLAUDE.md > Mandatory Math-Critic Gate.' "$producer")
  jq -nc --arg reason "$reason" '{decision:"block", reason:$reason}'
  exit 0
}

# Append-and-evaluate guarded by flock so two concurrent Agent calls cannot
# corrupt the log or race the gate check.
{
  flock -x 9

  case "$SUBAGENT" in
    ml-engineer|dl-engineer|ai-engineer)
      printf '%s PRODUCER %s\n' "$NANOS" "$SUBAGENT" >> "$SESSION_LOG"
      ;;
    math-critic)
      printf '%s MATH_OK -\n' "$NANOS" >> "$SESSION_LOG"
      ;;
    code-critic)
      # Read most recent producer and most recent math-critic events.
      LAST_PROD_LINE=$(grep ' PRODUCER ' "$SESSION_LOG" 2>/dev/null | tail -n 1 || true)
      LAST_MATH_LINE=$(grep ' MATH_OK ' "$SESSION_LOG" 2>/dev/null | tail -n 1 || true)

      if [[ -n "$LAST_PROD_LINE" ]]; then
        LAST_PROD_TS=$(printf '%s' "$LAST_PROD_LINE" | awk '{print $1}')
        LAST_PROD_AGENT=$(printf '%s' "$LAST_PROD_LINE" | awk '{print $3}')
        LAST_MATH_TS=""
        [[ -n "$LAST_MATH_LINE" ]] && LAST_MATH_TS=$(printf '%s' "$LAST_MATH_LINE" | awk '{print $1}')

        # Compare epoch-nanos as integers (both fit in 64 bits well past 2262).
        if [[ -z "$LAST_MATH_TS" ]] || [[ "$LAST_MATH_TS" -lt "$LAST_PROD_TS" ]]; then
          printf '%s GATE_VIOLATION %s\n' "$NANOS" "$LAST_PROD_AGENT" >> "$SESSION_LOG"
          # Release lock before emitting (emit_block exits).
          flock -u 9
          emit_block "$LAST_PROD_AGENT"
        fi
      fi
      printf '%s CODE_CRITIC_OK -\n' "$NANOS" >> "$SESSION_LOG"
      ;;
  esac
} 9>"$LOCK_FILE"

exit 0
