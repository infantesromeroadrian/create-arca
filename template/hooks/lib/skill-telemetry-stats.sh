#!/bin/bash
# ARCA — Skill telemetry stats updater (Hermes-3, Idea 3)
#
# Increments a counter inside ~/.claude/state/skill-telemetry-stats.json.
# Bucket name is the first positional arg. Buckets:
#   total_invocations    — every PostToolUse:Skill payload landed in the JSONL
#   unique_skills        — sum of distinct-skills-per-window across runs
#                          (window appearances, NOT lifetime-unique skills);
#                          a skill seen on 5 weekly runs adds 5, not 1.
#   weeks_processed      — bumped once per /skill-effectiveness run that wrote a report
#   effectiveness_runs   — bumped on every /skill-effectiveness invocation
#   flagged_skills_total — sum of skills below threshold across all runs
#
# Sibling pattern of justification-stats.sh / auto-adr-stats.sh /
# diff-comprehension-stats.sh / engram-nudge-stats.sh. ARCA-DEBT-001
# extends to 5-way: same read-modify-write race window. Stats here are
# observability — never the source of truth for any decision — so the
# lost-increment risk is accepted. Migrate to flock atomic update if
# these counters ever drive alerting or rate-limiting.

set -uo pipefail

bucket="${1:-unknown}"
STATS_FILE="${ARCA_SKILL_TELEMETRY_STATS_FILE:-${HOME}/.claude/state/skill-telemetry-stats.json}"

command -v jq >/dev/null 2>&1 || exit 0

mkdir -p "$(dirname "$STATS_FILE")" 2>/dev/null || exit 0

if [[ ! -f "$STATS_FILE" ]]; then
    cat > "$STATS_FILE" <<'EOF'
{
  "total_invocations": 0,
  "unique_skills": 0,
  "weeks_processed": 0,
  "effectiveness_runs": 0,
  "flagged_skills_total": 0,
  "first_seen": null,
  "last_updated": null
}
EOF
fi

now=$(date -Iseconds)
tmp="${STATS_FILE}.tmp.$$"
LOCK_FILE="${STATS_FILE}.lock"

# Atomic increment guarded by flock — closes ARCA-DEBT-001 5-way leg
# for skill-telemetry. The previous comment tracking the debt across
# all five sibling helpers is now redundant: every helper applies the
# same flock pattern as of this commit.
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
