#!/usr/bin/env bash
# ARCA — Proposal Gate · Agent marker (ADR-102). PreToolUse(Agent).
#
# The companion to proposal-gate.sh. Sets agent_dispatched=true on the current
# session's turn state the moment ARCA dispatches ANY Agent call. That single
# flag does double duty (ADR-102 §2.3, §5.2):
#   - it is the operational definition of "ARCA already proposed/delegated this
#     turn" — so proposal-gate.sh stays silent for the rest of the turn, and
#   - it is the subagent-immunity mechanism — a subagent's Bash/Edit only runs
#     because an Agent call created it, and that call passed through here first,
#     so the working specialist is never nudged.
#
# Fail-safe, advisory-free: exit 0 on every path, NEVER blocks the Agent call,
# emits nothing to stdout. A missed write only costs a spurious (soft) nudge
# later — acceptable; blocking a delegation would be catastrophic.
#
# INERT until registered in ~/.claude/settings.json under PreToolUse matcher
# "Agent" (paired with proposal-gate.sh under "Bash|Edit|Write"). See ADR-102 §5.
#
# Test override: ARCA_PROPOSAL_GATE_STATE points the state file elsewhere.

set -uo pipefail
umask 077

[[ "${ARCA_PROPOSAL_GATE_DISABLE:-0}" == "1" ]] && exit 0

payload="$(cat -)"
command -v jq >/dev/null 2>&1 || exit 0

session=$(printf '%s' "$payload" | jq -r '.session_id // empty' 2>/dev/null || echo "")
session="${session:0:36}"
[[ -z "$session" ]] && exit 0

STATE_DIR="${HOME}/.claude/state"
STATE_FILE="${ARCA_PROPOSAL_GATE_STATE:-${STATE_DIR}/proposal-gate.json}"
LOCK_FILE="${STATE_FILE}.lock"
mkdir -p "$STATE_DIR" 2>/dev/null || exit 0
[[ -w "$STATE_DIR" ]] || exit 0

# Upsert agent_dispatched=true for this session. Creates the session entry if
# the reflex reset has not run (e.g. a delegation outside a classified turn) —
# harmless: without a domain, proposal-gate.sh treats the turn as silent anyway.
(
    flock -w 1 9 || exit 0
    [[ -f "$STATE_FILE" ]] || echo '{}' > "$STATE_FILE" 2>/dev/null
    tmp="${STATE_FILE}.tmp.$$"
    if jq --arg s "$session" \
          '.[$s] = (.[$s] // {}) | .[$s].agent_dispatched = true' \
          "$STATE_FILE" > "$tmp" 2>/dev/null; then
        mv "$tmp" "$STATE_FILE" 2>/dev/null
    else
        rm -f "$tmp"
    fi
) 9>"$LOCK_FILE"

exit 0
