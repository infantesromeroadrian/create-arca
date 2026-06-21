#!/bin/bash
# ARCA — Engram Nudge stats updater (Hermes Idea 2 telemetry).
#
# Increments a counter inside ~/.claude/state/engram-nudges-stats.json.
# Counter buckets:
#   runs                — total invocations of engram-pattern-detector-cron.sh
#   clusters_found      — clusters that crossed MIN_CLUSTER_COUNT
#   useful              — clusters the LLM judge classified as useful
#   noise               — clusters the LLM judge classified as noise
#   timeout             — clusters where the judge timed out (fail-closed → noise)
#   weeks_with_output   — runs that produced a non-empty <YYYY-Www>.md file
#
# Pattern lifted from hooks/lib/auto-adr-stats.sh: idempotent, silent,
# fail-open. Concurrent writes can lose an increment under load
# (read-modify-write race) but stats here are observability — the same
# acceptable risk profile as the sibling scripts. Migrate to flock if
# counters ever drive a decision (alerting threshold, retraining gate).

set -uo pipefail

bucket="${1:-unknown}"
STATS_FILE="${ENGRAM_NUDGE_STATS_FILE:-${HOME}/.claude/state/engram-nudges-stats.json}"

command -v jq >/dev/null 2>&1 || exit 0

mkdir -p "$(dirname "$STATS_FILE")"

if [[ ! -f "$STATS_FILE" ]]; then
    cat > "$STATS_FILE" <<'EOF'
{
  "runs": 0,
  "clusters_found": 0,
  "useful": 0,
  "noise": 0,
  "timeout": 0,
  "weeks_with_output": 0,
  "first_seen": null,
  "last_updated": null
}
EOF
fi

now=$(date -Iseconds)
tmp="${STATS_FILE}.tmp.$$"
LOCK_FILE="${STATS_FILE}.lock"

# Atomic increment guarded by flock — closes the engram leg of
# ARCA-DEBT-001. Same flock pattern as the four sibling stats helpers.
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
