#!/bin/bash
set -uo pipefail
umask 077

# PostToolUse hook (matcher: Agent) — HARD-BLOCK enforcer for the
# Dynamic Orchestration code-critic gate (ADR-089, Layer 2 runtime).
#
# WHY THIS EXISTS (the gap it closes):
#   code-critic-gate-enforcer.sh fires only on the fixed closers
#   chief-architect|deployment. A *bespoke* dynamic DAG (ADR-089) may
#   produce code but end on some OTHER node (e.g. @docs-writer). That DAG
#   would not trip the code-critic gate at runtime. This hook treats the
#   DAG's DECLARED terminal node (a node with "is_terminal_closer": true
#   in the APPROVED orchestration proposal) as an additional phase-closer,
#   closing the gap WITHOUT touching the three existing enforcers
#   (Surgical Changes, Karpathy #3).
#
# ENFORCEMENT ONLY APPLIES when an approved dynamic orchestration proposal
# is active. In fixed-pipeline mode (no approved proposal in the project),
# this hook is a no-op and the three existing enforcers carry the load.
#
# SEMANTICS (mirrors code-critic-gate-enforcer.sh):
#   - Each code-producer invocation -> log line "PRODUCER <agent>"
#   - Each code-critic call          -> log line "CODE_CRITIC_OK -"
#   - Declared-terminal-closer invocation:
#       if last PRODUCER newer than last CODE_CRITIC_OK -> VIOLATION -> block.
#       else                                            -> log TERMINAL_CLOSER.
#
# PROPOSAL DISCOVERY:
#   - ARCA_DYNORCH_PROPOSAL (test/override): a single proposal JSON path.
#   - Otherwise: glob "<cwd>/docs/architecture/*-orchestration.json" and
#     collect terminal-closer agents from every proposal whose
#     .approval.status == "APPROVED". cwd comes from the hook input's
#     .cwd field, falling back to $PWD.
#
# Hardening (copied from code-critic-gate-enforcer.sh):
#   - SESSION_ID sanitized to [A-Za-z0-9_-], capped 64 chars.
#   - Epoch-nanosecond timestamps for same-second ordering.
#   - State log read/write guarded by flock.
#   - umask 077 keeps state files private.
#   - jq required; missing -> silent exit 0.
#   - All early-exit branches are exit 0 (silent). Only a real gate
#     violation emits the JSON block decision on stdout.
#
# Test overrides:
#   ARCA_DYNORCH_GATE_STATE_DIR  -> isolated state dir.
#   ARCA_DYNORCH_PROPOSAL        -> single proposal file (skips cwd glob).

INPUT=$(cat)

command -v jq >/dev/null 2>&1 || exit 0

TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || echo "")
[[ "$TOOL_NAME" != "Agent" ]] && exit 0

SUBAGENT=$(printf '%s' "$INPUT" | jq -r '.tool_input.subagent_type // empty' 2>/dev/null || echo "")
SESSION_ID_RAW=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || echo "")
[[ -z "$SUBAGENT" || -z "$SESSION_ID_RAW" ]] && exit 0

SESSION_ID=$(printf '%s' "$SESSION_ID_RAW" | tr -cd 'A-Za-z0-9_-' | cut -c1-64)
[[ -z "$SESSION_ID" ]] && exit 0

# --- Resolve the set of declared terminal-closer agents -------------------
# If no approved dynamic proposal is active, this hook does nothing.
collect_terminal_closers() {
  # Emits one closer-agent name per line across all approved proposals.
  if [[ -n "${ARCA_DYNORCH_PROPOSAL:-}" ]]; then
    [[ -f "$ARCA_DYNORCH_PROPOSAL" ]] || return 0
    jq -r 'select(.approval.status=="APPROVED")
           | .nodes[]? | select(.is_terminal_closer==true) | .agent' \
      "$ARCA_DYNORCH_PROPOSAL" 2>/dev/null
    return 0
  fi

  local cwd
  cwd=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || echo "")
  [[ -z "$cwd" ]] && cwd="${PWD:-.}"
  local dir="${cwd}/docs/architecture"
  [[ -d "$dir" ]] || return 0

  local f
  for f in "$dir"/*-orchestration.json; do
    [[ -f "$f" ]] || continue
    jq -r 'select(.approval.status=="APPROVED")
           | .nodes[]? | select(.is_terminal_closer==true) | .agent' \
      "$f" 2>/dev/null
  done
}

# Newline-separated set of closer agents; empty -> fixed mode, no-op.
CLOSERS=$(collect_terminal_closers | grep -v '^$' | sort -u || true)
[[ -z "$CLOSERS" ]] && exit 0

is_declared_closer() {
  # Exact line match against the resolved closer set.
  printf '%s\n' "$CLOSERS" | grep -qxF "$1"
}

# Same 17 code-producing agents as code-critic-gate-enforcer.sh
# (source: rules/compliance-ruleset.json CODE-CRITIC-GATE).
is_producer() {
  case "$1" in
    ml-engineer|dl-engineer|ai-engineer|ai-production-engineer| \
    data-engineer|python-specialist|tester|devops| \
    monitoring|api-designer|frontend-ai|mlops-engineer| \
    aws-engineer|rag-engineer|agent-engineer|gpu-engineer|deployment)
      return 0 ;;
    *) return 1 ;;
  esac
}

STATE_DIR="${ARCA_DYNORCH_GATE_STATE_DIR:-${HOME}/.claude/state/dynamic-orchestration-gate}"
mkdir -p "$STATE_DIR" 2>/dev/null || exit 0
SESSION_LOG="${STATE_DIR}/${SESSION_ID}.log"
LOCK_FILE="${SESSION_LOG}.lock"

NANOS=$(date +%s%N)

emit_block() {
  local producer="$1"
  local closer="$2"
  local reason
  reason=$(printf '[DYNAMIC-ORCHESTRATION-GATE] terminal closer @%s invoked without @code-critic approving @%s output. A bespoke DAG (ADR-089) that produces code must pass @code-critic before its declared terminal node. Required: producer -> @debt-detector -> @code-critic -> @%s.' "$closer" "$producer" "$closer")
  jq -nc --arg reason "$reason" '{decision:"block", reason:$reason}'
  exit 0
}

{
  flock -x 9

  if is_declared_closer "$SUBAGENT"; then
    LAST_PROD_LINE=$(grep ' PRODUCER ' "$SESSION_LOG" 2>/dev/null | tail -n 1 || true)
    LAST_CC_LINE=$(grep ' CODE_CRITIC_OK ' "$SESSION_LOG" 2>/dev/null | tail -n 1 || true)

    if [[ -n "$LAST_PROD_LINE" ]]; then
      LAST_PROD_TS=$(printf '%s' "$LAST_PROD_LINE" | awk '{print $1}')
      LAST_PROD_AGENT=$(printf '%s' "$LAST_PROD_LINE" | awk '{print $3}')
      LAST_CC_TS=""
      [[ -n "$LAST_CC_LINE" ]] && LAST_CC_TS=$(printf '%s' "$LAST_CC_LINE" | awk '{print $1}')

      if [[ -z "$LAST_CC_TS" ]] || [[ "$LAST_CC_TS" -lt "$LAST_PROD_TS" ]]; then
        printf '%s GATE_VIOLATION closer=%s producer=%s\n' "$NANOS" "$SUBAGENT" "$LAST_PROD_AGENT" >> "$SESSION_LOG"
        flock -u 9
        emit_block "$LAST_PROD_AGENT" "$SUBAGENT"
      fi
    fi
    printf '%s TERMINAL_CLOSER %s\n' "$NANOS" "$SUBAGENT" >> "$SESSION_LOG"
  elif is_producer "$SUBAGENT"; then
    printf '%s PRODUCER %s\n' "$NANOS" "$SUBAGENT" >> "$SESSION_LOG"
  elif [[ "$SUBAGENT" == "code-critic" ]]; then
    printf '%s CODE_CRITIC_OK -\n' "$NANOS" >> "$SESSION_LOG"
  fi
} 9>"$LOCK_FILE"

exit 0
