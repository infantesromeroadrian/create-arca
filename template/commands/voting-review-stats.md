---
description: Aggregate stats from the last N /voting-review-team runs traced to LangSmith. Validates the acceptance bar promised in PR #8 (>=33% NEW finding rate from debate round).
allowed-tools: Bash(curl*), Bash(jq*)
---

Read the last N voting-review-team runs from LangSmith and aggregate
stats. Decision-grade output: shows whether the acceptance bar declared
in PR #8 ("at least 1 of every 3 uses must surface a NEW finding the
debate round catches and the v1 silos would miss") is being met in
practice.

## Usage

```
/voting-review-stats [N]
```

`N` defaults to 10. Minimum useful sample: 3 runs.

## Process

Execute the bash block below. It pulls runs tagged `arca` +
`voting-review-team`, computes the metrics, and prints a compact report.
No interactive prompts.

```bash
set -uo pipefail

LIMIT="${ARGUMENTS:-10}"
# Strip non-digits in case user passes "10 please" or similar.
LIMIT=$(printf '%s' "$LIMIT" | tr -cd '0-9')
[[ -z "$LIMIT" ]] && LIMIT=10

KEY="${LANGSMITH_API_KEY:-}"
if [[ -z "$KEY" ]]; then
    echo "[/voting-review-stats] LANGSMITH_API_KEY not set in env. Aborting." >&2
    exit 1
fi

API_URL="${LANGSMITH_API_URL:-https://eu.api.smith.langchain.com}"

# Query runs by tag. LangSmith /runs/query expects a POST with filter.
PAYLOAD=$(jq -n --argjson lim "$LIMIT" '{
    filter: "and(eq(tags, \"voting-review-team\"), eq(run_type, \"chain\"))",
    limit: $lim,
    order: "desc"
}')

RAW=$(curl -sS --max-time 10 \
    -X POST \
    -H "X-API-Key: $KEY" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" \
    "${API_URL}/runs/query" 2>&1)

if ! echo "$RAW" | jq . >/dev/null 2>&1; then
    echo "[/voting-review-stats] LangSmith query failed:" >&2
    printf '%s\n' "$RAW" | head -c 400 >&2
    exit 1
fi

# LangSmith may return { runs: [...] } or a bare array depending on
# endpoint version. Coerce both to a clean array via type check —
# `.runs // .` fails on bare arrays because the index is by string key.
RUNS=$(printf '%s' "$RAW" | jq 'if type == "array" then . else (.runs // []) end')
TOTAL=$(printf '%s' "$RUNS" | jq 'length')

if (( TOTAL == 0 )); then
    echo "[/voting-review-stats] No runs found yet. Run /voting-review-team a few times to populate."
    exit 0
fi

# Aggregations.
APPROVED=$(printf '%s' "$RUNS" | jq '[.[] | select(.outputs.verdict == "APPROVED")] | length')
CONDITIONAL=$(printf '%s' "$RUNS" | jq '[.[] | select(.outputs.verdict == "CONDITIONAL")] | length')
REJECTED=$(printf '%s' "$RUNS" | jq '[.[] | select(.outputs.verdict == "REJECTED")] | length')

WITH_NEW=$(printf '%s' "$RUNS" | jq '[.[] | select((.outputs.new_findings_count // 0) > 0)] | length')
NEW_RATE=$(awk -v w="$WITH_NEW" -v t="$TOTAL" 'BEGIN { printf "%.1f", (t>0 ? (100*w/t) : 0) }')

WITH_MOVES=$(printf '%s' "$RUNS" | jq '[.[] | select((.outputs.score_movements_count // 0) > 0)] | length')
MOVES_RATE=$(awk -v m="$WITH_MOVES" -v t="$TOTAL" 'BEGIN { printf "%.1f", (t>0 ? (100*m/t) : 0) }')

DEBATE_FIRED=$(printf '%s' "$RUNS" | jq '[.[] | select(.outputs.debate_round_fired == true)] | length')

AVG_DURATION=$(printf '%s' "$RUNS" | jq '[.[] | (.outputs.duration_s // 0) | tonumber] | add / length' 2>/dev/null)

echo "============================================================"
echo "  /voting-review-team — eval harness (last $TOTAL runs)"
echo "============================================================"
printf "  Verdicts:    APPROVED %d | CONDITIONAL %d | REJECTED %d\n" "$APPROVED" "$CONDITIONAL" "$REJECTED"
printf "  Debate fired: %d / %d runs\n" "$DEBATE_FIRED" "$TOTAL"
printf "  NEW findings rate: %s%% (%d / %d runs surfaced >=1 NEW finding)\n" "$NEW_RATE" "$WITH_NEW" "$TOTAL"
printf "  Score-move rate:   %s%% (%d / %d runs had a reviewer change score after debate)\n" "$MOVES_RATE" "$WITH_MOVES" "$TOTAL"
printf "  Avg duration:      %.0fs\n" "${AVG_DURATION:-0}"
echo "============================================================"

# Acceptance bar check (PR #8 promise: 1 of every 3 uses must surface
# NEW findings). Threshold env-overridable for early observation
# windows (lower bar) or after-the-fact tightening (higher bar).
THRESHOLD="${ARCA_VOTING_NEW_RATE_THRESHOLD:-33}"
if (( $(awk -v r="$NEW_RATE" -v t="$THRESHOLD" 'BEGIN { print (r >= t) }') == 1 )); then
    echo "  ACCEPTANCE BAR: MET (>= ${THRESHOLD}%). v2 stays in main."
else
    echo "  ACCEPTANCE BAR: NOT MET (${NEW_RATE}% < ${THRESHOLD}%)."
    if (( TOTAL >= 3 )); then
        echo "  Recommendation: archive v2 and revert to v1. See PR #8 acceptance criterion."
    else
        echo "  Sample too small (need >= 3 runs). Re-evaluate after more usage."
    fi
fi
echo "============================================================"
```

## Decision rule

- `NEW findings rate >= 33%` AND `total runs >= 3` → v2 justifies its
  cost. Continue.
- `NEW findings rate < 33%` AND `total runs >= 3` → archive v2, revert
  to v1.
- `total runs < 3` → premature, gather more data.

## Out of scope

- Per-target trend (does v2 catch more on hooks/ vs agents/?).
- Reviewer-specific accuracy (which of P/A/Adversary contributes most
  NEW findings).
- Time-series plot of NEW rate over weeks. Add if `engram` integration
  becomes interesting.
