#!/usr/bin/env bash
# PreToolUse hook (matcher: Agent) — invokes scripts/skill_router_hybrid.py
# BEFORE every Agent() dispatch to surface deterministic skill routing
# confidence as advisory context.
#
# Per ADR-078 the hybrid routing algorithm (cosine + BM25 70/30, calibrated
# confidence alta/media/baja/none) exists as an executable script but was NOT
# wired into the delegation runtime — @skill-router was still LLM-served.
# This hook closes that loop.
#
# MODES:
#   - SHADOW (default): runs the router, logs the recommendation to stderr
#       and to ~/.claude/skill-router-suggestions.jsonl. Returns exit 0
#       regardless of confidence. The main loop sees the advisory but is
#       NOT blocked. This is the safe baseline while the corpus quality
#       gap (ADR-078 Consequences §"Corpus quality") is still open.
#   - ENFORCE (ARCA_SKILL_ROUTER_ENFORCE=1): if confidence == "none",
#       returns exit 2 with a stderr message that triggers Claude Code's
#       block behaviour. Only enable after corpus enrichment (ADR-079
#       follow-up) lifts the false-negative rate.
#
# WHITELIST:
#   The same set @delegation-preflight-enforcer skips. Re-running the
#   router for utility / gate agents would add noise (these agents
#   carry their own context and do not consume skills from the index).
#
# DEGRADES GRACEFULLY:
#   Missing jq, missing python, missing cache file, missing script —
#   all return exit 0 silently. The router is advisory; it must never
#   become a single point of failure in the dispatch pipeline.
#
# INVARIANTS:
#   - Reads stdin once (PreToolUse payload).
#   - Stateless across invocations.
#   - Writes telemetry append-only.
#   - Timeout-friendly (whole hook should finish in <500ms for cached
#     model; first run slower because sentence-transformers cold-loads).

set -uo pipefail

INPUT=$(cat)
LOG_FILE="${HOME}/.claude/skill-router-suggestions.jsonl"
ENFORCE="${ARCA_SKILL_ROUTER_ENFORCE:-0}"

# Degrade gracefully without jq or python.
command -v jq >/dev/null 2>&1 || exit 0

# Only act on Agent tool dispatch.
TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || echo "")
[[ "$TOOL_NAME" != "Agent" ]] && exit 0

SUBAGENT=$(printf '%s' "$INPUT" | jq -r '.tool_input.subagent_type // empty' 2>/dev/null || echo "")
[[ -z "$SUBAGENT" ]] && exit 0

# Extract the prompt the orchestrator is about to send to the subagent.
# Fallback to description if prompt is unavailable.
PROMPT=$(printf '%s' "$INPUT" | jq -r '.tool_input.prompt // .tool_input.description // empty' 2>/dev/null || echo "")
[[ -z "$PROMPT" ]] && exit 0

SESSION=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || echo "")

# ────────────────────────────────────────────────────────────────────────
# Whitelist — agents that do NOT benefit from skill routing
# ────────────────────────────────────────────────────────────────────────
WHITELIST=(
    "git-master" "docs-writer" "cost-analyzer" "sensei"
    "token-optimizer" "skill-router" "prompt-engineer"
    "math-critic" "code-critic" "debt-detector" "model-evaluator"
    "arca-ambient-monitor"
    "general-purpose" "Explore" "Plan" "statusline-setup" "claude-code-guide"
)
for w in "${WHITELIST[@]}"; do
    [[ "$SUBAGENT" == "$w" ]] && exit 0
done

# ────────────────────────────────────────────────────────────────────────
# Locate repo + python interpreter
# ────────────────────────────────────────────────────────────────────────
# Resolve repo root from ARCA_REPO, falling back to the canonical A.R.C.A/
# location if the env is unset or stale (e.g. inherited from a terminal opened
# before the repos were grouped under the A.R.C.A/ mother folder, 2026-06-14).
REPO_ROOT="${ARCA_REPO:-$HOME/Desktop/⟦ host_alias ⟧/A.R.C.A/.claude}"
[[ -d "$REPO_ROOT" ]] || REPO_ROOT="$HOME/Desktop/⟦ host_alias ⟧/A.R.C.A/.claude"
SCRIPT="${REPO_ROOT}/scripts/skill_router_hybrid.py"
PY="${REPO_ROOT}/.venv/bin/python"

[[ -x "$SCRIPT" ]] || exit 0
[[ -x "$PY" ]] || exit 0

# Truncate very long prompts to keep BM25 tokenisation reasonable
# (cosine handles long input fine, BM25 noises if prompt overwhelms corpus).
TASK="${PROMPT:0:2000}"

# ────────────────────────────────────────────────────────────────────────
# Run router (capture JSON, isolate failures)
# ────────────────────────────────────────────────────────────────────────
ROUTER_JSON=$(timeout 10 "$PY" "$SCRIPT" \
    --task "$TASK" \
    --agent "$SUBAGENT" \
    --json-only 2>/dev/null) || exit 0

[[ -z "$ROUTER_JSON" ]] && exit 0

CONFIDENCE=$(printf '%s' "$ROUTER_JSON" | jq -r '.confidence // "none"' 2>/dev/null)
TOP_NAMES=$(printf '%s' "$ROUTER_JSON" | jq -r '[.skills_selected[].name] | join(", ")' 2>/dev/null)
TOP_HYBRID=$(printf '%s' "$ROUTER_JSON" | jq -r '.skills_selected[0].hybrid // 0' 2>/dev/null)

# ────────────────────────────────────────────────────────────────────────
# Telemetry — append-only JSONL
# ────────────────────────────────────────────────────────────────────────
{
    jq -nc \
        --arg ts "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
        --arg session "$SESSION" \
        --arg agent "$SUBAGENT" \
        --arg confidence "$CONFIDENCE" \
        --arg top_names "$TOP_NAMES" \
        --argjson top_hybrid "$TOP_HYBRID" \
        --arg mode "$([[ "$ENFORCE" == "1" ]] && echo enforce || echo shadow)" \
        '{ts:$ts, session:$session, agent:$agent, confidence:$confidence, top_hybrid:$top_hybrid, top_names:$top_names, mode:$mode}' \
        >> "$LOG_FILE"
} 2>/dev/null || true

# ────────────────────────────────────────────────────────────────────────
# Stderr advisory — visible in main loop, non-blocking by default
# ────────────────────────────────────────────────────────────────────────
echo "[ARCA-SKILL-ROUTER] @${SUBAGENT} → confidence=${CONFIDENCE} hybrid=${TOP_HYBRID} top=[${TOP_NAMES:-none}]" >&2

# ────────────────────────────────────────────────────────────────────────
# Enforce mode — only blocks when confidence is "none"
# ────────────────────────────────────────────────────────────────────────
if [[ "$ENFORCE" == "1" && "$CONFIDENCE" == "none" ]]; then
    echo "[ARCA-SKILL-ROUTER] BLOCK: routing found no skills above THRESHOLD (0.35) for @${SUBAGENT}. Escalate to @architect-ai or refine the task description." >&2
    exit 2
fi

exit 0
