#!/usr/bin/env bash
# ARCA — Proposal Gate (ADR-102). PreToolUse(Bash|Edit|Write).
#
# Closes BEHAV-02 ("EL HUECO", audit 2026-06-11): today, if ARCA freelances a
# domain task in prose and runs a raw primitive (Bash/Edit/Write) WITHOUT first
# proposing routing, no gate fires — delegation-preflight-enforcer.sh only
# covers PreToolUse:Agent (the path that is ALREADY delegating). This hook adds
# a SOFT, escalating nudge on the bypass path. It NEVER blocks.
#
# ─── THE NON-NEGOTIABLE CONTRACT ──────────────────────────────────────────
# exit 0 ON EVERY PATH. This hook runs before the busiest tools in the system
# (Bash/Edit/Write). A non-zero exit or a hang would block ARCA's own
# primitives — the worst possible regression (ADR-102 §6). Every failure mode
# (no jq, no session, unwritable state, jq error, flock timeout, corrupt state)
# returns 0 and lets the tool proceed. It emits, at most, advisory
# `hookSpecificOutput.additionalContext` — NEVER `{"decision":"block"}` /
# `permissionDecision:"deny"`.
#
# ─── HOW IT KNOWS ─────────────────────────────────────────────────────────
# State (per session) is written by two cooperating hooks, NOT by this one:
#   - orchestration-reflex.sh (UserPromptSubmit) resets the turn and records
#     {domain, specialist, tier, primitives:0, agent_dispatched:false}.
#   - proposal-gate-agent-marker.sh (PreToolUse:Agent) sets agent_dispatched=true
#     the moment ARCA delegates to ANY subagent.
# This hook only READS domain/agent_dispatched and INCREMENTS primitives.
#
#   domain == ""            → not a recognised domain turn  → silent (inherits
#                             orchestration-reflex.sh's Layer-0 discipline).
#   agent_dispatched == true → ARCA already delegated this turn → silent. This
#                             is ALSO the subagent-immunity mechanism: a
#                             subagent's Bash/Edit only exists because an Agent
#                             call created it, and that call set the flag — so a
#                             working specialist is never nudged (ADR-102 §2.3).
#   else                    → increment primitive count, escalate per level.
#
# ─── ACTIVATION (deliberately NOT wired yet) ──────────────────────────────
# This hook is INERT until registered in ~/.claude/settings.json under
# PreToolUse with matcher "Bash|Edit|Write" (alongside proposal-gate-agent-marker.sh
# under "Agent"). Per ADR-102 §5, the threshold is left at its default until
# SF-1 telemetry (reflex-telemetry.jsonl) gives a real fire-rate to calibrate
# against. See docs/runbooks/ for the activation flip.
#
# Disable (even once wired): ARCA_PROPOSAL_GATE_DISABLE=1.
# Test override: ARCA_PROPOSAL_GATE_STATE points the state file elsewhere;
#                ARCA_PROPOSAL_GATE_THRESHOLD overrides the hint threshold.

set -uo pipefail
umask 077

[[ "${ARCA_PROPOSAL_GATE_DISABLE:-0}" == "1" ]] && exit 0

payload="$(cat -)"
command -v jq >/dev/null 2>&1 || exit 0

# A session id is required to scope state — without it we cannot tell turns
# apart, so fail safe (silent) rather than guess.
session=$(printf '%s' "$payload" | jq -r '.session_id // empty' 2>/dev/null || echo "")
session="${session:0:36}"
[[ -z "$session" ]] && exit 0

STATE_DIR="${HOME}/.claude/state"
STATE_FILE="${ARCA_PROPOSAL_GATE_STATE:-${STATE_DIR}/proposal-gate.json}"
LOCK_FILE="${STATE_FILE}.lock"

# No state file yet means no domain turn was ever recorded → nothing to gate.
[[ -f "$STATE_FILE" ]] || exit 0

# Read the turn's classification (fail-safe defaults on any jq error).
domain=$(jq -r --arg s "$session" '.[$s].domain // ""' "$STATE_FILE" 2>/dev/null || echo "")
agent_dispatched=$(jq -r --arg s "$session" '.[$s].agent_dispatched // false' "$STATE_FILE" 2>/dev/null || echo "false")
specialist=$(jq -r --arg s "$session" '.[$s].specialist // ""' "$STATE_FILE" 2>/dev/null || echo "")
tier=$(jq -r --arg s "$session" '.[$s].tier // ""' "$STATE_FILE" 2>/dev/null || echo "")
main_pid=$(jq -r --arg s "$session" '.[$s].main_pid // ""' "$STATE_FILE" 2>/dev/null || echo "")

# Not a recognised domain turn → no nudge (inherits the reflex's Layer-0).
[[ -z "$domain" ]] && exit 0

# Subagent immunity — PRIMARY mechanism (ADR-102 §2.3/§5.6). The main loop is
# the only context that receives UserPromptSubmit, so orchestration-reflex.sh
# stamps its claude-ancestor PID as main_pid. A primitive whose claude ancestor
# differs is a subagent doing delegated work → stay silent. This is turn-
# INDEPENDENT, so a long-lived teammate (Agent Teams) keeps immunity across the
# per-turn reset that clears agent_dispatched. If process identity cannot be
# resolved we do NOT silence on this basis (would make the gate useless) — the
# agent_dispatched flag below still covers the same-process, same-turn case.
if [[ -n "$main_pid" ]]; then
    # ARCA_PROPOSAL_GATE_CPID lets tests inject the resolved PID; in production
    # it is unset and we walk the process tree for the claude ancestor.
    my_pid="${ARCA_PROPOSAL_GATE_CPID:-}"
    if [[ -z "$my_pid" ]]; then
        cpid_lib="$(dirname "${BASH_SOURCE[0]}")/lib/claude-process-id.sh"
        [[ -r "$cpid_lib" ]] && my_pid=$(bash "$cpid_lib" 2>/dev/null || echo "")
    fi
    [[ -n "$my_pid" && "$my_pid" != "$main_pid" ]] && exit 0
fi

# Same-turn immunity — SECONDARY (ADR-102 §5.2). If ARCA already delegated this
# turn (any Agent call set the flag), the main loop's own later primitives are
# not freelancing → no nudge. Turn-scoped by design; the PID check above is what
# carries immunity across turns for still-running subagents.
[[ "$agent_dispatched" == "true" ]] && exit 0

# Atomically increment the per-session primitive counter. On any failure
# (flock timeout, jq error) we DROP to a silent exit — never block.
new=$(
    ( flock -w 1 9 || { echo 0; exit; }
      cur=$(jq -r --arg s "$session" '.[$s].primitives // 0' "$STATE_FILE" 2>/dev/null)
      cur=${cur:-0}
      [[ "$cur" =~ ^[0-9]+$ ]] || cur=0
      n=$((cur + 1))
      tmp="${STATE_FILE}.tmp.$$"
      if jq --arg s "$session" --argjson n "$n" \
            '.[$s] = (.[$s] // {}) | .[$s].primitives = $n' \
            "$STATE_FILE" > "$tmp" 2>/dev/null; then
          mv "$tmp" "$STATE_FILE" 2>/dev/null
      else
          rm -f "$tmp"
      fi
      echo "$n"
    ) 9>"$LOCK_FILE"
)
new=${new:-0}
[[ "$new" =~ ^[0-9]+$ ]] || exit 0

# Threshold for Level 1 (Hint). Open parameter ADR-102 §5.1 — default 2nd
# primitive (the 1st is always-silent exploration grace). Calibrate vs SF-1.
THRESH="${ARCA_PROPOSAL_GATE_THRESHOLD:-2}"
[[ "$THRESH" =~ ^[0-9]+$ ]] || THRESH=2

# Below the threshold → silent (exploration grace).
[[ "$new" -lt "$THRESH" ]] && exit 0

# Build the escalating, FACTUAL (non-imperative, ADR-102 §5.3) advisory.
who="${specialist:-the owning specialist}"
what_tier=""
[[ -n "$tier" ]] && what_tier=" (TIER-${tier^^} per ADR-101)"

if   [[ "$new" -eq "$THRESH" ]]; then
    # Level 1 — Hint
    msg="$new domain primitives on a '${domain}' turn with no routing proposal yet. The owning specialist (${who}) has not been proposed${what_tier}. (ADR-091/101 reflex.)"
elif [[ "$new" -eq $((THRESH + 1)) ]]; then
    # Level 2 — Warning
    msg="$new domain primitives on a '${domain}' turn, still no routing proposal. Pattern of prose-freelancing forming — the owning specialist is ${who}${what_tier}. Propose routing before continuing (ADR-091/101)."
else
    # Level 3 — Strong (repeats each further primitive)
    msg="$new domain primitives on a '${domain}' turn with no proposal. This is the recurring orchestration-discipline failure (Engram feedback_orchestration_discipline). Owning specialist: ${who}${what_tier}. ARCA is meant to propose routing, not freelance domain work in prose (ADR-091/101/102)."
fi

# Advisory channel ONLY. additionalContext reaches the model; never blocks.
jq -nc --arg c "$msg" \
   '{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $c}}' \
   2>/dev/null || true

exit 0
