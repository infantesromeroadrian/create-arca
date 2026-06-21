#!/bin/bash
# ARCA - Phase transition detector (UserPromptSubmit).
#
# ⟦ user_name ⟧'s principle: each phase refines the project via its mandatory
# gates; skipping a phase silently degrades pipeline quality. This hook
# detects natural-language attempts to advance the pipeline phase and
# blocks the prompt if any blocking gate of the current phase is unsigned.
#
# Detection patterns (Spanish + English, case-insensitive):
#   - "vamos a C<N>" / "let's go to C<N>"
#   - "cerramos C<N>" / "close C<N>"
#   - "pasamos a C<N>" / "advance to C<N>" / "move to C<N>"
#   - "siguiente ciclo" / "next phase" / "next cycle"
#   - "fase <N>" / "ciclo <N>" / "phase <N>"
#
# When a transition request is detected:
#   1. Compute current phase from arca-pipeline-state.json.
#   2. Read blocking gates list from hooks/lib/phase-gates.json.
#   3. Compare with gates_signed_current_phase.
#   4. If missing gates -> exit 2 with explanatory stderr.
#   5. If all blocking gates present -> exit 0 (advance authorized;
#      actual state transition happens via /close-phase command).
#
# Bypass: BYPASS_PHASE_TRANSITION=1 (logged).

set -uo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-${PWD}}"
LIB="${PROJECT_DIR}/hooks/lib/phase-state.sh"
LOG="${HOME}/.claude/state/phase-transition-audit.log"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || true

[[ -f "$LIB" ]] || exit 0
# shellcheck source=/dev/null
. "$LIB"

# ADR-037: meta-ecosystem repos have no pipeline state. Exit silently.
phase_state_is_dormant && exit 0

if [[ "${BYPASS_PHASE_TRANSITION:-}" == "1" ]]; then
    printf '%s | bypass | reason=%s\n' "$(date -Iseconds)" "${BYPASS_REASON:-no-reason}" >> "$LOG"
    exit 0
fi

command -v jq >/dev/null 2>&1 || exit 0

INPUT="$(cat 2>/dev/null || true)"
[[ -z "$INPUT" ]] && exit 0

prompt=$(printf '%s' "$INPUT" | jq -r '.user_prompt // .prompt // empty' 2>/dev/null)
[[ -z "$prompt" ]] && exit 0

# Pattern detection: did the user ask to advance phase?
trigger_pattern='vamos\s+a\s+[Cc][0-9]+|cerramos\s+[Cc][0-9]+|pasamos\s+a\s+[Cc][0-9]+|siguiente\s+(ciclo|fase)|next\s+(phase|cycle)|advance\s+to\s+[Cc][0-9]+|move\s+to\s+[Cc][0-9]+|close\s+[Cc][0-9]+|fase\s+[0-9]+|ciclo\s+[0-9]+'

if ! echo "$prompt" | grep -qiE "$trigger_pattern"; then
    exit 0
fi

current=$(phase_state_current)
[[ -z "$current" ]] && current="C1"

# Collect blocking gates for current phase
mapfile -t blocking < <(phase_blocking_gates_for "$current")
mapfile -t signed   < <(phase_state_gates_signed)

missing=()
for g in "${blocking[@]}"; do
    found=0
    for s in "${signed[@]}"; do
        [[ "$s" == "$g" ]] && { found=1; break; }
    done
    (( found == 0 )) && missing+=("$g")
done

if (( ${#missing[@]} > 0 )); then
    {
        echo "BLOCKED by ARCA Phase Gate enforcer."
        echo
        echo "You appear to be requesting a phase transition while the"
        echo "current phase (${current}) has unsigned BLOCKING gates."
        echo
        echo "Phase: ${current}"
        echo "Missing blocking gates:"
        for g in "${missing[@]}"; do
            echo "  - @${g}"
        done
        echo
        echo "Resolve by invoking each missing gate (Task tool) and letting"
        echo "phase-gate-enforcer.sh register their signatures, OR run"
        echo "/close-phase ${current} which validates and advances."
        echo
        echo "Emergency bypass (logged): export BYPASS_PHASE_TRANSITION=1"
    } >&2
    printf '%s | block | phase=%s | missing=%s\n' \
        "$(date -Iseconds)" "$current" "${missing[*]}" >> "$LOG"
    exit 2
fi

printf '%s | allow | phase=%s | blocking_all_signed\n' \
    "$(date -Iseconds)" "$current" >> "$LOG"
exit 0
