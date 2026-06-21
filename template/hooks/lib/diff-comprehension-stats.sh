#!/bin/bash
# ARCA — Diff Comprehension Gate v2 stats updater
#
# Increments a counter inside ~/.claude/state/diff-comprehension-stats.json.
# The bucket name is the first positional arg. Buckets:
#   approved             — judge returned APPROVED, merge allowed
#   blocked_timeout      — user did not type a summary in time
#   blocked_incoherent   — judge said summary contradicts diff
#   blocked_shallow      — judge said summary is too generic
#   bypass               — ARCA_DIFF_BYPASS=1 used (also audit-logged)
#   v1_fallback_no_tty   — non-interactive shell, fell back to v1 word count
#   v1_fallback_judge    — Ollama down / judge timeout, fell back to v1
#   reused_recent        — cached APPROVED verdict re-used within TTL
#
# This script is a sibling of hooks/lib/justification-stats.sh (same
# atomicity caveats apply, see TODO below). Counters are observability,
# not the source of truth for any decision — failures are swallowed.

set -uo pipefail

bucket="${1:-unknown}"
STATS_FILE="${HOME}/.claude/state/diff-comprehension-stats.json"

command -v jq >/dev/null 2>&1 || exit 0

mkdir -p "$(dirname "$STATS_FILE")"

if [[ ! -f "$STATS_FILE" ]]; then
    cat > "$STATS_FILE" <<'EOF'
{
  "approved": 0,
  "blocked_timeout": 0,
  "blocked_incoherent": 0,
  "blocked_shallow": 0,
  "bypass": 0,
  "v1_fallback_no_tty": 0,
  "v1_fallback_judge": 0,
  "reused_recent": 0,
  "first_seen": null,
  "last_updated": null
}
EOF
fi

now=$(date -Iseconds)
tmp="${STATS_FILE}.tmp.$$"
LOCK_FILE="${STATS_FILE}.lock"

# Atomic increment guarded by flock — closes ARCA-DEBT-001 (E.3 leg).
# Same rationale as justification-stats.sh: prevents lost increments
# under concurrent invocations.
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
