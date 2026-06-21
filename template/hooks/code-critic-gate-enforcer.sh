#!/bin/bash
set -uo pipefail
umask 077

# PostToolUse hook (matcher: Agent) — HARD-BLOCK enforcer for the
# Mandatory Code-Critic Gate.
#
# Rule (CLAUDE.md > Mandatory Code-Critic Gate):
#   Agents that produce code must be followed by @code-critic before
#   phase transition.
#
# TRIGGER DESIGN — why only two closers:
#   Unlike the math-critic gate (3 producers, 1 consumer, linear chain),
#   the code-critic gate has 17 producers and no natural "phase
#   transition" tool_use event. Enforcing on every producer would break
#   legitimate chains (ml-engineer -> dl-engineer -> ai-engineer).
#   The only unambiguous "closing" events are:
#     - @chief-architect — F6 mandatory blocking gate before deploy
#     - @deployment      — F6 serving, the literal act of deploy
#   Enforcing code-critic before either captures real intent with
#   zero false positives on producer chains.
#
# SEMANTICS:
#   - Each producer invocation  -> log line "PRODUCER <agent>"
#   - Each code-critic call     -> log line "CODE_CRITIC_OK -"
#   - Phase-closer invocation (chief-architect|deployment):
#       if last PRODUCER newer than last CODE_CRITIC_OK -> VIOLATION -> block.
#       else                                            -> log PHASE_CLOSER.
#
#   `deployment` is BOTH a producer (emits Dockerfile/FastAPI code) AND a
#   phase-closer. It is routed to the closer branch first: invoking
#   @deployment without prior @code-critic is itself a violation.
#
# Hardening (copied from math-critic-gate-enforcer.sh):
#   - SESSION_ID sanitized to [A-Za-z0-9_-], truncated to 64 chars.
#   - Epoch-nanosecond timestamps so two events in the same wall-clock
#     second can be ordered correctly.
#   - State log read/write guarded by flock so concurrent Agent calls
#     cannot interleave.
#   - umask 077 keeps state files private.
#   - jq required; missing -> silent exit 0 (telemetry degrades).
#   - All early-exit branches are exit 0 (silent). Only an actual
#     gate violation emits the JSON block decision on stdout.
#
# Claude Code PostToolUse contract:
#   Valid JSON on stdout with {"decision":"block","reason":"..."} triggers
#   a hard block on the next model turn, with the reason shown in the
#   transcript. Reference: docs.claude.com/en/docs/claude-code/hooks.
#
# Test override: ARCA_CODE_CRITIC_GATE_STATE_DIR redirects state to an
# isolated tmpdir for pytest/shell tests.

INPUT=$(cat)

# jq is mandatory to parse hook input safely.
command -v jq >/dev/null 2>&1 || exit 0

TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || echo "")
[[ "$TOOL_NAME" != "Agent" ]] && exit 0

SUBAGENT=$(printf '%s' "$INPUT" | jq -r '.tool_input.subagent_type // empty' 2>/dev/null || echo "")
SESSION_ID_RAW=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || echo "")
[[ -z "$SUBAGENT" || -z "$SESSION_ID_RAW" ]] && exit 0

# Sanitize session_id against path traversal. Keep [A-Za-z0-9_-] only
# (no dots: './' and '..' survive slash stripping via '.'). Cap length
# at 64 to bound state-file names.
SESSION_ID=$(printf '%s' "$SESSION_ID_RAW" | tr -cd 'A-Za-z0-9_-' | cut -c1-64)
[[ -z "$SESSION_ID" ]] && exit 0

STATE_DIR="${ARCA_CODE_CRITIC_GATE_STATE_DIR:-${HOME}/.claude/state/code-critic-gate}"
mkdir -p "$STATE_DIR" 2>/dev/null || exit 0
SESSION_LOG="${STATE_DIR}/${SESSION_ID}.log"
LOCK_FILE="${SESSION_LOG}.lock"

NANOS=$(date +%s%N)

# emit_block — write the JSON hard-block contract to stdout, exit 0.
# exit 2 would be wrong here: Claude Code reads stdout JSON for the
# decision field, and exit 0 keeps the contract clean.
emit_block() {
  local producer="$1"
  local closer="$2"
  local reason
  reason=$(printf '[CODE-CRITIC-GATE] @%s invoked without @code-critic approving @%s output. Required chain: producer -> @debt-detector -> @code-critic -> @%s. See CLAUDE.md > Mandatory Code-Critic Gate.' "$closer" "$producer" "$closer")
  jq -nc --arg reason "$reason" '{decision:"block", reason:$reason}'
  exit 0
}

# 17 code-producing agents (source: rules/compliance-ruleset.json).
is_producer() {
  case "$1" in
    ml-engineer|dl-engineer|ai-engineer|ai-production-engineer| \
    data-engineer|python-specialist|tester|devops| \
    monitoring|api-designer|frontend-ai|mlops-engineer| \
    aws-engineer|rag-engineer|agent-engineer|gpu-engineer)
      return 0 ;;
    *) return 1 ;;
  esac
}

# Phase-closers. `deployment` is also a producer; it is intentionally
# routed through this check first so invoking it without a prior
# code-critic on the last producer blocks correctly.
is_phase_closer() {
  case "$1" in
    chief-architect|deployment) return 0 ;;
    *) return 1 ;;
  esac
}

# Append-and-evaluate guarded by flock so two concurrent Agent calls
# cannot corrupt the log or race the gate check.
{
  flock -x 9

  if is_phase_closer "$SUBAGENT"; then
    LAST_PROD_LINE=$(grep ' PRODUCER ' "$SESSION_LOG" 2>/dev/null | tail -n 1 || true)
    LAST_CC_LINE=$(grep ' CODE_CRITIC_OK ' "$SESSION_LOG" 2>/dev/null | tail -n 1 || true)

    if [[ -n "$LAST_PROD_LINE" ]]; then
      LAST_PROD_TS=$(printf '%s' "$LAST_PROD_LINE" | awk '{print $1}')
      LAST_PROD_AGENT=$(printf '%s' "$LAST_PROD_LINE" | awk '{print $3}')
      LAST_CC_TS=""
      [[ -n "$LAST_CC_LINE" ]] && LAST_CC_TS=$(printf '%s' "$LAST_CC_LINE" | awk '{print $1}')

      # Compare epoch-nanos as integers (both fit 64-bit well past 2262).
      if [[ -z "$LAST_CC_TS" ]] || [[ "$LAST_CC_TS" -lt "$LAST_PROD_TS" ]]; then
        printf '%s GATE_VIOLATION closer=%s producer=%s\n' "$NANOS" "$SUBAGENT" "$LAST_PROD_AGENT" >> "$SESSION_LOG"
        flock -u 9
        emit_block "$LAST_PROD_AGENT" "$SUBAGENT"
      fi
    fi
    printf '%s PHASE_CLOSER %s\n' "$NANOS" "$SUBAGENT" >> "$SESSION_LOG"
  elif is_producer "$SUBAGENT"; then
    printf '%s PRODUCER %s\n' "$NANOS" "$SUBAGENT" >> "$SESSION_LOG"
  elif [[ "$SUBAGENT" == "code-critic" ]]; then
    printf '%s CODE_CRITIC_OK -\n' "$NANOS" >> "$SESSION_LOG"
  fi
} 9>"$LOCK_FILE"

exit 0
