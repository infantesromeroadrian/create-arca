#!/bin/bash
set -uo pipefail
umask 077

# PostToolUse hook — Tracks code-critic rejections for auto-tuning.
#
# When an agent gets rejected by code-critic >2 times, flags it for
# prompt-engineer review on next session startup.
#
# DETECTION POLICY (P1-13 fix, audit 2026-05-15):
#   Primary marker: response contains `VEREDICTO:` followed by
#     `BLOQUEADO` or `BLOQUEANTE` (the code-critic.md output contract
#     line 313: "VEREDICTO: BLOQUEADO / APROBADO CON ADVERTENCIAS /
#     APROBADO"). Robust against bag-of-words false positives like
#     a critic explaining why something is NOT rejected.
#   Fallback marker: legacy bag-of-words regex retained for responses
#     that don't follow the contract (older critics, third-party
#     compatible output). Kept as second-chance detection.
#
# RESET POLICY:
#   If the agent's prompt file (agents/<name>.md) changes between
#   rejections, the counter resets to 0 and the pending flag is
#   cleared. The stored prompt hash is updated. This way a completed
#   auto-tune (prompt edited by @prompt-engineer) clears the alert
#   without manual intervention.
#
# ADR-041 extension: when an agent first enters auto_tune_pending,
# this hook writes `pending_since[agent] = ISO8601 now`. The companion
# hook auto-tune-aging-detector.sh consumes that timestamp to compute
# aging and emit severity-tiered warnings on session start. Hash-change
# reset also deletes the pending_since entry.
#
# CONCURRENCY (P1-13 fix):
#   Read-modify-write on critic_rejections.json is wrapped in flock(2)
#   so concurrent Agent invocations cannot race and clobber each other.
#   umask 077 at top of file keeps the state file private (rejected
#   agent names are sensitive — they signal training quality issues).

STATE_DIR="${HOME}/.claude/state"
TRACKER_FILE="${STATE_DIR}/critic_rejections.json"
LOCK_FILE="${TRACKER_FILE}.lock"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

mkdir -p "$STATE_DIR"

prompt_hash() {
    local agent="$1"
    local file="${REPO_ROOT}/agents/${agent}.md"
    [ -f "$file" ] || { echo ""; return; }
    sha256sum "$file" | awk '{print $1}'
}

# Detect rejection per the new policy. Returns 0 (blocked) or 1 (not).
# Order matters: try the structured marker first, fall back to bag-of-
# words for legacy or third-party critic outputs.
detect_blocked() {
    local response="$1"
    # Primary: structured VEREDICTO marker. Matches the code-critic.md
    # output contract. Case-insensitive on the verdict word so future
    # variants like "Veredicto:" / "VEREDICTO:" both hit.
    if printf '%s' "$response" | grep -qiE 'VEREDICTO:[[:space:]]*(BLOQUEADO|BLOQUEANTE)'; then
        return 0
    fi
    # Fallback: legacy bag-of-words. Kept for compatibility but known
    # to false-positive on negations ("este código no está bloqueado").
    # Future critics SHOULD emit VEREDICTO; this is the safety net.
    if printf '%s' "$response" | grep -qiE 'BLOQUEANTE|rechazado|rejected|blocked|no aprueba'; then
        return 0
    fi
    return 1
}

# Atomic mutate_state — wraps a jq filter in flock + tmp-and-mv so two
# concurrent invocations cannot interleave. The jq filter receives the
# tracker via stdin and must emit the new tracker on stdout.
mutate_state() {
    local jq_filter="$1"
    shift  # remaining args are passed to jq as --arg/--argjson pairs

    # Block up to 5s for the lock; if we never get it, drop the event
    # silently rather than blocking forever (telemetry must not deadlock).
    (
        flock -w 5 9 || exit 1
        local tmp="${TRACKER_FILE}.tmp.$$"
        jq "$@" "$jq_filter" "$TRACKER_FILE" > "$tmp" 2>/dev/null \
            && mv "$tmp" "$TRACKER_FILE" \
            || rm -f "$tmp"
    ) 9>"$LOCK_FILE"
}

# ─── Hook body ────────────────────────────────────────────────────────

INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

# Only track Agent tool results (subagent completions)
case "$TOOL_NAME" in
    Agent) ;;
    *) exit 0 ;;
esac

# Check if the tool response contains code-critic rejection patterns
RESPONSE=$(echo "$INPUT" | jq -r '.tool_response // empty' 2>/dev/null)
[ -z "$RESPONSE" ] && exit 0

# Only track responses that are *from* code-critic. The check used to be
# a bag-of-words on "code-critic" in the response — kept here as the
# scope guard (the agent name is in tool_input.subagent_type for
# Anthropic-spec Agent tool calls).
SUBAGENT=$(echo "$INPUT" | jq -r '.tool_input.subagent_type // empty' 2>/dev/null)
if [ "$SUBAGENT" != "code-critic" ]; then
    # Pre-ADR-043 fallback — accept responses that mention code-critic
    # in body for the rare case where the orchestrator describes the
    # gate result inline. Keeps backward compat with the old hook
    # behavior while the new path is the primary.
    if ! echo "$RESPONSE" | grep -qiE '@?code[-_]critic'; then
        exit 0
    fi
fi

# ─── ADR-100: Re-review runtime cap (Max-2-cycles enforcement) ──────────
# Count code-critic INVOCATIONS per (session, artifact) — distinct from the
# per-agent, cross-session rejection counting below (which feeds auto-tune).
# On the 3rd invocation over the SAME artifact in the SAME session, emit
# decision:block: the next model turn is stopped and the artifact's disposition
# becomes an @architect-ai decision (docs/audit-policy.md "Max 2 cycles" +
# ADR-100). Reuses this file's state store + $LOCK_FILE flock — no parallel
# tracker. Fail-safe: no session_id or no derivable artifact key → no block.
CAP_SESSION=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null | tr -cd 'A-Za-z0-9_-')
if [ -n "$CAP_SESSION" ]; then
    # Artifact key = hash of the sorted set of file paths the critic prompt
    # references (same files under review across cycles → same key). Falls back
    # to the description hash; if neither yields a key, skip the cap (fail-safe).
    CAP_PROMPT=$(echo "$INPUT" | jq -r '.tool_input.prompt // empty' 2>/dev/null)
    CAP_PATHS=$(printf '%s' "$CAP_PROMPT" | grep -oE '[A-Za-z0-9_./-]+\.(sh|py|md|json|ts|tsx|js|yaml|yml|toml|sql)' | sort -u)
    if [ -n "$CAP_PATHS" ]; then
        CAP_ART=$(printf '%s' "$CAP_PATHS" | sha256sum | awk '{print $1}' | cut -c1-16)
    else
        CAP_DESC=$(echo "$INPUT" | jq -r '.tool_input.description // empty' 2>/dev/null)
        [ -n "$CAP_DESC" ] && CAP_ART=$(printf '%s' "$CAP_DESC" | sha256sum | awk '{print $1}' | cut -c1-16) || CAP_ART=""
    fi
    if [ -n "$CAP_ART" ]; then
        CAP_KEY="${CAP_SESSION}:${CAP_ART}"
        # Atomic increment of cycles[CAP_KEY] under the same flock; echo new count.
        CAP_NEW=$(
            ( flock -w 5 9 || { echo 0; exit; }
              [ -f "$TRACKER_FILE" ] || echo '{"rejections":{},"auto_tune_pending":[],"prompt_hashes":{},"pending_since":{},"cycles":{}}' > "$TRACKER_FILE"
              cur=$(jq -r --arg k "$CAP_KEY" '.cycles[$k] // 0' "$TRACKER_FILE" 2>/dev/null); cur=${cur:-0}
              new=$((cur + 1))
              tmp="${TRACKER_FILE}.tmp.cap.$$"
              jq --arg k "$CAP_KEY" --argjson n "$new" '.cycles = (.cycles // {}) | .cycles[$k] = $n' "$TRACKER_FILE" > "$tmp" 2>/dev/null \
                  && mv "$tmp" "$TRACKER_FILE" || rm -f "$tmp"
              echo "$new"
            ) 9>"$LOCK_FILE"
        )
        CAP_NEW=${CAP_NEW:-0}
        if [ "$CAP_NEW" -ge 3 ]; then
            jq -nc --arg r "3rd @code-critic cycle on the same artifact this session — Max-2-cycles reached (docs/audit-policy.md + ADR-100). STOP re-reviewing: escalate this artifact's disposition to @architect-ai for a deciding judgment." '{decision:"block", reason:$r}'
            exit 0
        fi
    fi
fi
# ─── end ADR-100 cap ────────────────────────────────────────────────────

# Apply detection policy
detect_blocked "$RESPONSE" || exit 0

# Extract the agent being reviewed. When code-critic runs in chain after
# a producer, the response typically names the producer; absent a
# parseable name, this hook degrades gracefully (no-op).
AGENT_NAME=$(echo "$INPUT" | jq -r '.tool_input.description // empty' 2>/dev/null \
             | grep -oE '@[a-z][a-z0-9-]*' | head -1 | tr -d '@')
if [ -z "$AGENT_NAME" ]; then
    AGENT_NAME=$(echo "$INPUT" | jq -r '.tool_input.name // empty' 2>/dev/null)
fi
[ -z "$AGENT_NAME" ] && exit 0

# Initialize tracker (atomic; flock + jq pattern via mutate_state).
if [ ! -f "$TRACKER_FILE" ]; then
    (
        flock -w 5 9 || exit 1
        # Re-check inside the lock — another process may have just
        # initialized it.
        if [ ! -f "$TRACKER_FILE" ]; then
            echo '{"rejections": {}, "auto_tune_pending": [], "prompt_hashes": {}, "pending_since": {}, "cycles": {}}' > "$TRACKER_FILE"
        fi
    ) 9>"$LOCK_FILE"
fi

# Ensure backward-compat keys exist on older state files.
mutate_state '. + {prompt_hashes: (.prompt_hashes // {}), pending_since: (.pending_since // {}), cycles: (.cycles // {})}'

# Reset-on-prompt-change: if the agent prompt file changed since the
# last rejection, counter goes back to 0 and the pending flag is cleared.
CURRENT_HASH=$(prompt_hash "$AGENT_NAME")
STORED_HASH=$(jq -r --arg a "$AGENT_NAME" '.prompt_hashes[$a] // ""' "$TRACKER_FILE" 2>/dev/null)

if [ -n "$CURRENT_HASH" ] && [ "$CURRENT_HASH" != "$STORED_HASH" ]; then
    mutate_state '.rejections[$a] = 0
                  | .auto_tune_pending = (.auto_tune_pending | map(select(. != $a)))
                  | .prompt_hashes[$a] = $h
                  | del(.pending_since[$a])' \
        --arg a "$AGENT_NAME" --arg h "$CURRENT_HASH"
    echo "Prompt de @${AGENT_NAME} cambió — contador de rejections reseteado." >&2
fi

# Increment rejection count for this agent.
CURRENT=$(jq -r --arg a "$AGENT_NAME" '.rejections[$a] // 0' "$TRACKER_FILE" 2>/dev/null)
NEW_COUNT=$((CURRENT + 1))

mutate_state '.rejections[$a] = $c' \
    --arg a "$AGENT_NAME" --argjson c "$NEW_COUNT"

# If >2 rejections, add to auto-tune pending list and stamp pending_since
# (ADR-041). Only emit the alert once per (agent, prompt-hash) window.
if [ "$NEW_COUNT" -ge 3 ]; then
    ALREADY_PENDING=$(jq --arg a "$AGENT_NAME" \
        '[.auto_tune_pending[] | select(. == $a)] | length' "$TRACKER_FILE" 2>/dev/null)

    if [ "$ALREADY_PENDING" -eq 0 ]; then
        NOW_ISO=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        mutate_state '.auto_tune_pending += [$a]
                      | .pending_since[$a] = $t' \
            --arg a "$AGENT_NAME" --arg t "$NOW_ISO"
        echo "Agente @${AGENT_NAME} rechazado ${NEW_COUNT} veces por @code-critic. Marcado para auto-tuning con @prompt-engineer." >&2
    fi
fi

exit 0
