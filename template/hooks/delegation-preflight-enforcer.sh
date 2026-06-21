#!/usr/bin/env bash
# PreToolUse hook (matcher: Agent) — enforces the Delegation Pre-flight Checklist
# defined in CLAUDE.md:
#
#   [ ] 1. @token-optimizer called FIRST (compress context to <=670 tokens)
#   [ ] 2. @skill-router called SECOND (select <=3 skills)
#   [ ] 3/4. Gate chain planning (math-critic/code-critic) — enforced elsewhere
#
# WHY this hook exists:
#   Sesión 2026-04-21 documented 3 violations of this checklist by the
#   orchestrator (see docs/ARCA_COMPLIANCE.md). math-critic-advisor.sh
#   reports to stderr but does not block; the rule was de facto optional.
#   This hook is the mechanical gate.
#
# SEMANTICS OF THE CHECK:
#   Checks that @token-optimizer and @skill-router appear ANYWHERE in the
#   current session (not just "last N events"). Rationale: Opus 4.8 can
#   tool-call several Agents in a single assistant turn. The PostToolUse of
#   @token-optimizer may not have flushed to telemetry.jsonl before the
#   PreToolUse of a downstream specialist fires. A window-based check would
#   produce false positives in that pattern. Session-wide check honours
#   the rule's intent ("think before delegating") without penalising legit
#   parallel orchestration.
#
# MODES:
#   - DRY-RUN (default, ARCA_PREFLIGHT_ENFORCE unset or !=1):
#       Logs violations to ~/.claude/preflight-violations.jsonl
#       Writes a one-line warning to stderr. Returns exit 0.
#   - ENFORCE (ARCA_PREFLIGHT_ENFORCE=1):
#       Logs violation AND returns exit 2 (blocks the Agent call).
#
# BYPASS:
#   - Write a reason to /tmp/arca-preflight-bypass. Single-use (moved atomically
#     on consumption to avoid race condition between parallel sessions).
#
# INVARIANTS:
#   - jq required; missing → exit 0 silently (telemetry degrades gracefully).
#   - Only inspects the CURRENT session_id.
#   - Whitelisted agents (utility + gate + tool-agents) always pass.
#   - Tolerant to corrupt lines in telemetry.jsonl (uses grep pre-filter,
#     not jq-parse the whole file, so a single bad line does not abort).

set -euo pipefail

INPUT=$(cat)
LOG_FILE="${HOME}/.claude/preflight-violations.jsonl"
BYPASS_FILE="/tmp/arca-preflight-bypass"
ENFORCE="${ARCA_PREFLIGHT_ENFORCE:-0}"

# Degrade gracefully without jq — never break the flow.
command -v jq >/dev/null 2>&1 || exit 0

TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || echo "")
[[ "$TOOL_NAME" != "Agent" ]] && exit 0

SUBAGENT=$(printf '%s' "$INPUT" | jq -r '.tool_input.subagent_type // empty' 2>/dev/null || echo "")
[[ -z "$SUBAGENT" ]] && exit 0

SESSION=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || echo "")

# ────────────────────────────────────────────────────────────────────────
# ADR-098: proportional fast-path inputs. A small single-domain brief does not
# need @token-optimizer (nothing to compress below its ~670-token floor); the
# enforcer waives the @token-optimizer requirement for it (rule 1). BRIEF_LEN is
# measured on the dispatch's own prompt. Rule 2 (skip BOTH when @skill-router
# would return 0-1 skills) is NOT implemented: that count is not recorded in any
# consumable telemetry today (the hybrid log emits a fixed top-3) — see ADR-098
# amendment. Scope is the preflight chain ONLY; the critic gate chain is untouched.
BRIEF=$(printf '%s' "$INPUT" | jq -r '.tool_input.prompt // empty' 2>/dev/null || echo "")
BRIEF_LEN=${#BRIEF}
PROPORTIONAL_FLOOR=2700   # ~670 tokens — @token-optimizer's own floor (token-optimizer.md:20)

# Multi-domain / orchestrator agents NEVER fast-path: they cross domains and
# benefit from compression even on a short brief. Conservative per ADR-098
# ("err toward full preflight on ambiguity").
MULTI_DOMAIN_AGENTS=(
    "architect-ai" "chief-architect" "compound-ai-architect"
    "ai-redteam-orchestrator" "htb-orchestrator" "team-composer" "project-planner"
)
is_single_domain() {
    local name="$1" a
    for a in "${MULTI_DOMAIN_AGENTS[@]}"; do
        [[ "$name" == "$a" ]] && return 1
    done
    return 0
}

# ────────────────────────────────────────────────────────────────────────
# Whitelist — agents that do NOT require preflight (CLAUDE.md §Excepciones)
# ────────────────────────────────────────────────────────────────────────
UTILITY_AGENTS=(
    "git-master"
    "docs-writer"
    "cost-analyzer"
    "sensei"
    "token-optimizer"
    "skill-router"
    "prompt-engineer"
)

# Gate/review agents audit existing context; no fresh delegation load.
GATE_AGENTS=(
    "math-critic"
    "code-critic"
    "debt-detector"
    "model-evaluator"
    "arca-ambient-monitor"
)

OTHER_EXEMPT=(
    "general-purpose"
    "Explore"
    "Plan"
    "statusline-setup"
    "claude-code-guide"
)

is_whitelisted() {
    local name="$1"
    local a
    for a in "${UTILITY_AGENTS[@]}" "${GATE_AGENTS[@]}" "${OTHER_EXEMPT[@]}"; do
        [[ "$name" == "$a" ]] && return 0
    done
    return 1
}

if is_whitelisted "$SUBAGENT"; then
    exit 0
fi

# ────────────────────────────────────────────────────────────────────────
# Bypass — race-safe single-use consumption via atomic rename
# ────────────────────────────────────────────────────────────────────────
if [[ -f "$BYPASS_FILE" ]]; then
    # Move atomically so concurrent preflight runs do not double-spend.
    BYPASS_CLAIMED="${BYPASS_FILE}.consumed.$$"
    if mv "$BYPASS_FILE" "$BYPASS_CLAIMED" 2>/dev/null; then
        REASON=$(cat "$BYPASS_CLAIMED" 2>/dev/null || echo "no-reason-given")
        rm -f "$BYPASS_CLAIMED"
        {
            jq -nc \
                --arg ts "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
                --arg type "preflight_bypass" \
                --arg agent "$SUBAGENT" \
                --arg session "$SESSION" \
                --arg reason "$REASON" \
                '{ts:$ts, type:$type, agent:$agent, session:$session, reason:$reason}' \
                >> "$LOG_FILE"
        } 2>/dev/null || true
        echo "[ARCA-PREFLIGHT] Bypass consumed for @${SUBAGENT}: ${REASON}" >&2
        exit 0
    fi
    # If mv failed, another concurrent invocation won the race. Fall through
    # and evaluate normally; if legitimately compliant, passes; else blocks.
fi

# ────────────────────────────────────────────────────────────────────────
# Compliance check — session-wide via grep (robust to corrupt JSONL lines)
# ────────────────────────────────────────────────────────────────────────
TELEMETRY="${HOME}/.claude/telemetry.jsonl"
TOKEN_OPT_CALLED=0
SKILL_ROUTER_CALLED=0

if [[ -f "$TELEMETRY" ]] && [[ -n "$SESSION" ]]; then
    # grep pipeline: O(n) single pass, tolerates corrupt JSONL lines.
    # DEFENSE IN DEPTH — pre-filter by "type":"agent_invocation" BEFORE
    # matching the session and agent. This prevents a false positive where
    # another event type (e.g. a tool_use with a description string
    # containing the literal `"agent":"token-optimizer"`) would wrongly
    # satisfy the preflight. Closes debt D1 (code-critic A.1 review).
    #
    # NOTE: redirecting grep output to /dev/null (not `-q`) avoids a SIGPIPE
    # from `pipefail` when grep short-circuits on first match under large
    # inputs. Regression caught in tests/test_preflight_enforcer.sh (1000
    # noise events) after the D1 refactor.
    if grep -F '"type":"agent_invocation"' "$TELEMETRY" 2>/dev/null \
        | grep -F "\"session\":\"${SESSION}\"" 2>/dev/null \
        | grep -F '"agent":"token-optimizer"' >/dev/null 2>&1; then
        TOKEN_OPT_CALLED=1
    fi
    if grep -F '"type":"agent_invocation"' "$TELEMETRY" 2>/dev/null \
        | grep -F "\"session\":\"${SESSION}\"" 2>/dev/null \
        | grep -F '"agent":"skill-router"' >/dev/null 2>&1; then
        SKILL_ROUTER_CALLED=1
    fi
fi

# Compliant fast-path (full preflight done).
if [[ "$TOKEN_OPT_CALLED" == "1" ]] && [[ "$SKILL_ROUTER_CALLED" == "1" ]]; then
    exit 0
fi

# ────────────────────────────────────────────────────────────────────────
# ADR-098 proportional fast-path (rule 1): a small (< floor) single-domain brief
# does not require @token-optimizer — there is nothing to compress below its own
# floor. @skill-router is STILL required (skill selection is orthogonal to size).
# Logged as proportionality_skip, NOT a violation, so telemetry distinguishes a
# correct fast-path from an operator bypass.
# ────────────────────────────────────────────────────────────────────────
if [[ "$SKILL_ROUTER_CALLED" == "1" ]] && [[ "$TOKEN_OPT_CALLED" == "0" ]] \
   && [[ "$BRIEF_LEN" -lt "$PROPORTIONAL_FLOOR" ]] && is_single_domain "$SUBAGENT"; then
    {
        jq -nc \
            --arg ts "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
            --arg type "proportionality_skip" \
            --arg agent "$SUBAGENT" \
            --arg session "$SESSION" \
            --arg skipped "@token-optimizer" \
            --argjson brief_len "$BRIEF_LEN" \
            --argjson floor "$PROPORTIONAL_FLOOR" \
            '{ts:$ts, type:$type, agent:$agent, session:$session, skipped:$skipped, brief_len:$brief_len, floor:$floor, reason:"brief below @token-optimizer floor + single-domain target (ADR-098 rule 1)"}' \
            >> "$LOG_FILE"
    } 2>/dev/null || true
    echo "[ARCA-PREFLIGHT] proportionality_skip: @token-optimizer waived for @${SUBAGENT} (brief ${BRIEF_LEN} < ${PROPORTIONAL_FLOOR} chars, single-domain) — ADR-098 rule 1. @skill-router still required (present)." >&2
    exit 0
fi

# ────────────────────────────────────────────────────────────────────────
# Violation — record and report
# ────────────────────────────────────────────────────────────────────────
MISSING=()
[[ "$TOKEN_OPT_CALLED" == "0" ]] && MISSING+=("@token-optimizer")
[[ "$SKILL_ROUTER_CALLED" == "0" ]] && MISSING+=("@skill-router")

# Guard against empty MISSING (logically unreachable, but set -u is strict).
if [[ ${#MISSING[@]} -eq 0 ]]; then
    exit 0
fi

# Build the "missing" JSON array safely for any cardinality.
MISSING_JSON=$(printf '%s\n' "${MISSING[@]}" | jq -R . | jq -s . 2>/dev/null || echo '[]')

{
    jq -nc \
        --arg ts "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
        --arg type "preflight_violation" \
        --arg agent "$SUBAGENT" \
        --arg session "$SESSION" \
        --arg mode "$( [[ "$ENFORCE" == "1" ]] && echo "enforce" || echo "dry-run" )" \
        --argjson missing "$MISSING_JSON" \
        '{ts:$ts, type:$type, agent:$agent, session:$session, mode:$mode, missing:$missing}' \
        >> "$LOG_FILE"
} 2>/dev/null || true

MISSING_STR="${MISSING[*]}"

if [[ "$ENFORCE" == "1" ]]; then
    cat >&2 <<EOF
[ARCA-PREFLIGHT] BLOCKED delegation to @${SUBAGENT}.
Session: ${SESSION:-unknown}
Missing from this session: ${MISSING_STR}
Required by CLAUDE.md §Delegation Pre-flight Checklist.

To proceed (pick one):
  (a) Invoke the missing agents in the current session, then retry:
        ${MISSING_STR}
  (b) Emergency bypass (single-use, logged):
        echo "reason" > /tmp/arca-preflight-bypass
        (then retry)
EOF
    exit 2
else
    echo "[ARCA-PREFLIGHT] DRY-RUN: would block @${SUBAGENT} in session ${SESSION:-?} (missing: ${MISSING_STR}). Export ARCA_PREFLIGHT_ENFORCE=1 to enforce." >&2
    exit 0
fi
