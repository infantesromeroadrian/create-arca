#!/bin/bash
# ARCA - phase state helpers (sourced, not executed).
#
# State file: ~/.claude/state/arca-pipeline-state.json
# Shape:
# {
#   "active_project": "<basename of cwd or override>",
#   "current_phase": "C1",
#   "phase_history": [
#     {"phase":"C1","opened_at":"...","closed_at":"...","gates_passed":["project-planner"]}
#   ],
#   "gates_signed_current_phase": ["project-planner", ...]
# }

set -uo pipefail

STATE_FILE="${HOME}/.claude/state/arca-pipeline-state.json"
# ADR-068 30-day grace window: if the legacy ARES-era state file exists
# but the ARCA-era one does not, migrate it once (rename in place) so
# accumulated phase history survives the reversal.
_LEGACY_STATE_FILE="${HOME}/.claude/state/ares-pipeline-state.json"
if [[ -f "$_LEGACY_STATE_FILE" && ! -f "$STATE_FILE" ]]; then
    mv "$_LEGACY_STATE_FILE" "$STATE_FILE" 2>/dev/null || true
fi
unset _LEGACY_STATE_FILE
LOCK_FILE="${STATE_FILE}.lock"
PHASE_GATES_JSON="${HOME}/.claude/hooks/lib/phase-gates.json"
DENYLIST_FILE="${HOME}/.claude/hooks/lib/phase-state-denylist.txt"

# P0-H2 fix (audit 2026-05-16): atomic read-modify-write helper that
# wraps a jq filter in flock + tmp+mv so two concurrent hook invocations
# cannot race and clobber each other. Mirrors the pattern already
# applied in critic-feedback-tracker.sh::mutate_state() (P1-13 fix,
# 2026-05-15). Drop the event silently on lock starvation — phase state
# mutation must not deadlock the parent hook.
#
# Usage:
#   _phase_state_mutate '<jq filter>' --arg k v ...
_phase_state_mutate() {
    local jq_filter="$1"; shift
    (
        flock -w 5 9 || exit 1
        local tmp="${STATE_FILE}.tmp.$$"
        jq "$@" "$jq_filter" "$STATE_FILE" > "$tmp" 2>/dev/null \
            && mv "$tmp" "$STATE_FILE" \
            || rm -f "$tmp"
    ) 9>"$LOCK_FILE"
}

# ADR-037: pipeline state is reserved for ML pipeline projects, not for
# meta-ecosystem repos (.claude, your-snapshots-repo, etc).
# Returns 0 (true) when the current cwd MUST NOT have pipeline state.
phase_state_is_dormant() {
    [[ "${ARCA_PIPELINE_FORCE_INIT:-0}" == "1" ]] && return 1
    [[ -f "$DENYLIST_FILE" ]] || return 1
    local proj
    proj="$(basename "${PWD:-unknown}")"
    grep -qE "^${proj}$" "$DENYLIST_FILE" 2>/dev/null
}

phase_state_init() {
    [[ -f "$STATE_FILE" ]] && return 0
    phase_state_is_dormant && return 0
    mkdir -p "$(dirname "$STATE_FILE")" 2>/dev/null || true
    local proj
    proj="$(basename "${PWD:-unknown}")"
    cat > "$STATE_FILE" <<INNER
{
  "active_project": "${proj}",
  "current_phase": "C1",
  "opened_at": "$(date -Iseconds)",
  "phase_history": [],
  "gates_signed_current_phase": []
}
INNER
}

phase_state_current() {
    phase_state_is_dormant && { echo "DORMANT"; return 0; }
    phase_state_init
    [[ -f "$STATE_FILE" ]] || { echo "DORMANT"; return 0; }
    jq -r '.current_phase // "C1"' "$STATE_FILE"
}

phase_state_project() {
    phase_state_is_dormant && { echo ""; return 0; }
    phase_state_init
    [[ -f "$STATE_FILE" ]] || { echo ""; return 0; }
    jq -r '.active_project // "unknown"' "$STATE_FILE"
}

phase_state_gates_signed() {
    # echoes one gate name per line for the current phase. Empty when DORMANT.
    phase_state_is_dormant && return 0
    phase_state_init
    [[ -f "$STATE_FILE" ]] || return 0
    jq -r '.gates_signed_current_phase[]?' "$STATE_FILE"
}

phase_state_sign_gate() {
    # phase_state_sign_gate <agent_name>. No-op when DORMANT (ADR-037).
    # Atomic via _phase_state_mutate (P0-H2 fix).
    local gate="$1"
    [[ -z "$gate" ]] && return 1
    phase_state_is_dormant && return 0
    phase_state_init
    _phase_state_mutate '
        .gates_signed_current_phase += [$g]
        | .gates_signed_current_phase |= unique
    ' --arg g "$gate"
}

phase_state_advance() {
    # phase_state_advance <next_phase>. No-op when DORMANT (ADR-037).
    # Atomic via _phase_state_mutate (P0-H2 fix).
    local next="$1"
    [[ -z "$next" ]] && return 1
    phase_state_is_dormant && return 0
    phase_state_init
    _phase_state_mutate '
        .phase_history += [{
            "phase": .current_phase,
            "opened_at": .opened_at,
            "closed_at": $ts,
            "gates_passed": .gates_signed_current_phase
        }]
        | .current_phase = $next
        | .opened_at = $ts
        | .gates_signed_current_phase = []
    ' --arg next "$next" --arg ts "$(date -Iseconds)"
}

phase_gates_for() {
    # phase_gates_for <phase>  -> echoes gate names (one per line)
    local phase="$1"
    [[ -f "$PHASE_GATES_JSON" ]] || return 0
    jq -r --arg p "$phase" '.phases[$p].gates[]?' "$PHASE_GATES_JSON" 2>/dev/null
}

phase_blocking_gates_for() {
    # phase_blocking_gates_for <phase>  -> only blocking gates (one per line).
    # `.phases[$p].blocking` may be:
    #   - boolean true   → all gates of that phase are blocking
    #   - boolean false  → no blocking gates
    #   - array of names → those specific gates are blocking
    local phase="$1"
    [[ -f "$PHASE_GATES_JSON" ]] || return 0

    local blk_kind
    blk_kind=$(jq -r --arg p "$phase" '.phases[$p].blocking | type'         "$PHASE_GATES_JSON" 2>/dev/null)

    case "$blk_kind" in
        boolean)
            local is_block
            is_block=$(jq -r --arg p "$phase" '.phases[$p].blocking'                 "$PHASE_GATES_JSON" 2>/dev/null)
            [[ "$is_block" == "true" ]] && phase_gates_for "$phase"
            ;;
        array)
            jq -r --arg p "$phase" '.phases[$p].blocking[]?'                 "$PHASE_GATES_JSON" 2>/dev/null
            ;;
        *)
            : # null / missing → no blocking gates
            ;;
    esac
}
