#!/bin/bash
# ARCA — Auto-ADR stats updater (E.2)
#
# Increments a counter inside ~/.claude/state/auto-adr-stats.json.
# Counter buckets:
#   detected            — heuristic fired in @architect-ai output
#   suppressed_dup      — fired but rate-limited (same session+agent)
#   drafted_via_skill   — /adr-new produced a fresh NNN-slug.md
#   judge_pass          — /adr-validate accepted the file as complete
#   judge_fail          — /adr-validate flagged missing sections
#   bypass              — operator skipped the gate explicitly
#
# Pattern lifted from hooks/lib/justification-stats.sh: idempotent,
# silent, fail-open. Concurrent writes can lose an increment under load
# (read-modify-write race) but stats here are observability, not a
# decision input — same risk profile, same mitigation deferred.

set -uo pipefail

bucket="${1:-unknown}"
STATS_FILE="${HOME}/.claude/state/auto-adr-stats.json"

command -v jq >/dev/null 2>&1 || exit 0

mkdir -p "$(dirname "$STATS_FILE")"

if [[ ! -f "$STATS_FILE" ]]; then
    cat > "$STATS_FILE" <<'EOF'
{
  "detected": 0,
  "suppressed_dup": 0,
  "drafted_via_skill": 0,
  "judge_pass": 0,
  "judge_fail": 0,
  "bypass": 0,
  "first_seen": null,
  "last_updated": null
}
EOF
fi

now=$(date -Iseconds)
tmp="${STATS_FILE}.tmp.$$"
LOCK_FILE="${STATS_FILE}.lock"

# Atomic increment guarded by flock — closes ARCA-DEBT-001 (E.2 leg).
# Same rationale as justification-stats.sh: two concurrent invocations
# could both read the same base value, both compute +1, and the second mv
# would silently overwrite the first.
{
    flock -x 9
    jq --arg b "$bucket" --arg now "$now" '
        .[$b] = (.[$b] // 0) + 1
        | .first_seen = (.first_seen // $now)
        | .last_updated = $now
    ' "$STATS_FILE" > "$tmp" 2>/dev/null

    if [[ -s "$tmp" ]]; then
        mv "$tmp" "$STATS_FILE"
    else
        rm -f "$tmp"
    fi
} 9>"$LOCK_FILE"

exit 0
