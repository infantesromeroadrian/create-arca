#!/bin/bash
# ARCA — Claude Code config-guide gate stats updater (ADR-023 phase 2)
#
# Mirror of `justification-stats.sh`. Increments a counter inside
# ~/.claude/state/claude-code-guide-gate-stats.json. The counter name is
# the first positional arg and corresponds to the verdict ladder used by
# claude-code-config-guide-gate.sh.
#
# Buckets (phase 1 + phase 3 forward-looking):
#   - Phase 1 emits: skipped_no_path, skipped_path_oos, skipped_loc_low,
#     skipped_not_arca, skipped_phase1, cached_approved, bypass,
#     skipped_multiedit.
#   - Phase 3 will additionally emit: approved, drift_deprecated,
#     undocumented_field, schema_violation, timeout.
#
# The bucket set is open: any unknown bucket name passed in becomes a new
# zero-initialised key. Aggregation downstream (morning-briefing,
# guardian-audit) iterates the JSON object so adding new verdicts in
# future phases does not require touching this script.
#
# Idempotent and silent. Failures (jq missing, flock unavailable) are
# swallowed — stats are observability, not correctness. The audit log at
# ~/.claude/state/claude-code-guide-gate-audit.jsonl remains the
# authoritative trail; this file is the rolled-up summary.

set -uo pipefail

bucket="${1:-unknown}"
STATS_FILE="${HOME}/.claude/state/claude-code-guide-gate-stats.json"

command -v jq >/dev/null 2>&1 || exit 0

mkdir -p "$(dirname "$STATS_FILE")" 2>/dev/null || exit 0

# Initialise the file with the known bucket set if missing. Forward-
# looking values (phase 3 verdicts) are pre-zeroed so the morning
# briefing has a stable shape from day one.
if [[ ! -f "$STATS_FILE" ]]; then
    cat > "$STATS_FILE" <<'EOF'
{
  "skipped_no_path": 0,
  "skipped_path_oos": 0,
  "skipped_loc_low": 0,
  "skipped_not_arca": 0,
  "skipped_phase1": 0,
  "cached_approved": 0,
  "bypass": 0,
  "approved": 0,
  "drift_deprecated": 0,
  "undocumented_field": 0,
  "schema_violation": 0,
  "timeout": 0,
  "skipped_multiedit": 0,
  "first_seen": null,
  "last_updated": null
}
EOF
fi

now=$(date -Iseconds)
tmp="${STATS_FILE}.tmp.$$"
LOCK_FILE="${STATS_FILE}.lock"

# Atomic increment guarded by flock — same pattern as
# justification-stats.sh. Without the lock two concurrent invocations
# could both read the same base value, both compute +1, and the second
# mv would overwrite the first, dropping one count silently.
{
    flock -x 9
    jq --arg b "$bucket" --arg now "$now" '
        .[$b] = (.[$b] // 0) + 1
        | .last_updated = $now
        | (if .first_seen == null then .first_seen = $now else . end)
    ' "$STATS_FILE" > "$tmp" 2>/dev/null && mv "$tmp" "$STATS_FILE" 2>/dev/null
    rm -f "$tmp" 2>/dev/null
} 9>"$LOCK_FILE"

exit 0
