#!/usr/bin/env bash
# skills/skill-effectiveness/run.sh — Hermes-3 Idea 3 aggregator.
#
# Reads ~/.claude/state/skill-telemetry.jsonl (or override), filters
# records to the last N weeks, computes per-skill counts, and writes a
# weekly markdown report flagging skills whose success_rate falls below
# threshold AND whose total usage reaches the minimum sample size.
#
# Pure arithmetic — no LLM, no judge, no Ollama. The whole point of
# Idea 3 vs Idea 2 is to NOT introduce a fifth LLM judge into ARCA
# (ARCA-DEBT-001 already covers four). Aggregation is a fold over the
# JSONL with jq; flag rule is a single comparison.
#
# Args (read from stdin, single line):
#   [--weeks N]       window size, default 4
#   [--threshold X]   success-rate cutoff in [0, 1], default 0.7
#
# Constants:
#   MIN_TOTAL_FOR_FLAG = 10  (denominator must include >=10 records,
#                             counting success+fail+unknown — keeps
#                             low-sample skills out of the flag list)
#
# Output:
#   ~/.claude/state/skill-effectiveness/<YYYY-Www>.md
#
# Exit codes:
#   0  report written (or "no flags" notice written)
#   1  invalid argument value
#   2  environment error (jq missing, telemetry file unreadable, etc.)
#
# TEST OVERRIDES
#   ARCA_SKILL_TELEMETRY_FILE       — point at a synthetic JSONL.
#   ARCA_SKILL_EFFECTIVENESS_DIR    — redirect report output dir.
#   ARCA_SKILL_TELEMETRY_STATS_FILE — redirect stats counter file.
#   ARCA_SKILL_EFF_NOW              — fixed wallclock for deterministic
#                                     reports in tests (epoch seconds).

set -uo pipefail

readonly DEFAULT_WEEKS=4
readonly DEFAULT_THRESHOLD="0.7"
readonly MIN_TOTAL_FOR_FLAG=10

if ! command -v jq >/dev/null 2>&1; then
    echo "[/skill-effectiveness] ENTORNO: jq no disponible en PATH." >&2
    exit 2
fi

# Read flags from stdin (slash command pipes ARGS_RAW). Trimming and
# tokenizing keep the parser robust against extra whitespace from the
# heredoc body. The argv channel is intentionally unused — same reason
# /justify uses stdin: no argv re-evaluation surface.
ARGS_RAW=""
if [[ ! -t 0 ]]; then
    ARGS_RAW="$(cat)"
fi
ARGS_RAW="${ARGS_RAW%$'\n'}"
ARGS_TRIMMED="$(printf '%s' "$ARGS_RAW" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

WEEKS="$DEFAULT_WEEKS"
THRESHOLD="$DEFAULT_THRESHOLD"

# Parse `--weeks N` and `--threshold X` from the trimmed string. Using
# `read -ra` after `set --` keeps quoting predictable; positional args
# never come from argv.
if [[ -n "$ARGS_TRIMMED" ]]; then
    # shellcheck disable=SC2206
    TOKENS=($ARGS_TRIMMED)
    i=0
    n=${#TOKENS[@]}
    while (( i < n )); do
        case "${TOKENS[$i]}" in
            --weeks)
                i=$((i + 1))
                if (( i >= n )); then
                    echo "[/skill-effectiveness] ERROR: --weeks requires a value." >&2
                    exit 1
                fi
                WEEKS="${TOKENS[$i]}"
                ;;
            --threshold)
                i=$((i + 1))
                if (( i >= n )); then
                    echo "[/skill-effectiveness] ERROR: --threshold requires a value." >&2
                    exit 1
                fi
                THRESHOLD="${TOKENS[$i]}"
                ;;
            *)
                echo "[/skill-effectiveness] ERROR: unknown flag '${TOKENS[$i]}'." >&2
                echo "  Usage: /skill-effectiveness [--weeks N] [--threshold X]" >&2
                exit 1
                ;;
        esac
        i=$((i + 1))
    done
fi

# Validate WEEKS: positive integer.
if ! [[ "$WEEKS" =~ ^[1-9][0-9]*$ ]]; then
    echo "[/skill-effectiveness] ERROR: --weeks must be a positive integer; got '$WEEKS'." >&2
    exit 1
fi

# Validate THRESHOLD: float in (0, 1]. We let jq do the numeric parse
# so the canonical comparison below stays consistent with the report.
if ! THRESHOLD_OK=$(jq -n --arg t "$THRESHOLD" '
    ($t | tonumber? // null) as $n
    | if $n == null then "invalid"
      elif $n <= 0 or $n > 1 then "out_of_range"
      else "ok" end
' 2>/dev/null) || [[ "$THRESHOLD_OK" != "\"ok\"" ]]; then
    echo "[/skill-effectiveness] ERROR: --threshold must be a number in (0, 1]; got '$THRESHOLD'." >&2
    exit 1
fi

JSONL_FILE="${ARCA_SKILL_TELEMETRY_FILE:-${HOME}/.claude/state/skill-telemetry.jsonl}"
REPORT_DIR="${ARCA_SKILL_EFFECTIVENESS_DIR:-${HOME}/.claude/state/skill-effectiveness}"
mkdir -p "$REPORT_DIR" 2>/dev/null || {
    echo "[/skill-effectiveness] ENTORNO: cannot create $REPORT_DIR." >&2
    exit 2
}

# Wallclock honors ARCA_SKILL_EFF_NOW so tests can pin it.
NOW_EPOCH="${ARCA_SKILL_EFF_NOW:-$(date +%s)}"
WINDOW_SECONDS=$((WEEKS * 7 * 86400))
CUTOFF_EPOCH=$((NOW_EPOCH - WINDOW_SECONDS))

# ISO week id YYYY-Www of the report wallclock.
REPORT_ID=$(date -d "@${NOW_EPOCH}" +%G-W%V 2>/dev/null || date +%G-W%V)
REPORT_FILE="${REPORT_DIR}/${REPORT_ID}.md"

# Aggregate the JSONL with one jq pass.
#
# Per-skill object accumulates {total, success, fail, unknown, rate}.
# Records older than CUTOFF_EPOCH are dropped. Records that fail to
# parse a timestamp are dropped silently — JSONL is append-only so a
# rare bad record should not poison the report.
#
# Flag rule:
#   total >= MIN_TOTAL_FOR_FLAG  AND  success_rate < THRESHOLD
#
# success_rate denominator = success + fail (unknown excluded). When
# success+fail == 0 the skill cannot have a meaningful rate, so it is
# never flagged regardless of unknown count.
if [[ ! -f "$JSONL_FILE" ]]; then
    # No telemetry yet — emit empty-state report so callers always have
    # a file to point at.
    AGG_JSON='[]'
    TOTAL_INVOCATIONS=0
else
    AGG_JSON=$(jq -s --argjson cutoff "$CUTOFF_EPOCH" '
        # Parse ts as ISO-8601 with timezone offset. fromdateiso8601
        # only accepts the Z form, but the hook emits +HH:MM offsets
        # via `date -Iseconds`, so we use strptime|mktime which handles
        # %z correctly. Records that fail to parse are dropped silently
        # (rare malformed line should not poison the report).
        def parse_ts: try (strptime("%Y-%m-%dT%H:%M:%S%z") | mktime) catch null;
        map(. + {epoch: ((.ts // "") | parse_ts)})
        | map(select(.epoch != null and .epoch >= $cutoff))
        | group_by(.skill // "unknown")
        | map(
            (.[0].skill // "unknown") as $name
            | (length) as $total
            | (map(select(.outcome == "success")) | length) as $s
            | (map(select(.outcome == "fail")) | length) as $f
            | (map(select(.outcome == "unknown")) | length) as $u
            | (if ($s + $f) == 0 then null else ($s / ($s + $f)) end) as $rate
            | {skill: $name, total: $total, success: $s, fail: $f, unknown: $u, rate: $rate}
        )
        | sort_by(.rate // 1)
    ' "$JSONL_FILE" 2>/dev/null || echo '[]')

    TOTAL_INVOCATIONS=$(printf '%s' "$AGG_JSON" | jq '[.[].total] | add // 0' 2>/dev/null || echo 0)
fi

# Flag list: rate is non-null, total >= MIN_TOTAL_FOR_FLAG, rate < threshold.
FLAGGED_JSON=$(printf '%s' "$AGG_JSON" | jq --argjson min "$MIN_TOTAL_FOR_FLAG" --arg th "$THRESHOLD" '
    [.[] | select(
        .rate != null
        and .total >= $min
        and .rate < ($th | tonumber)
    )]
' 2>/dev/null || echo '[]')

FLAGGED_COUNT=$(printf '%s' "$FLAGGED_JSON" | jq 'length' 2>/dev/null || echo 0)
UNIQUE_SKILLS=$(printf '%s' "$AGG_JSON" | jq 'length' 2>/dev/null || echo 0)

# Render markdown report. Heredoc-piped to file via printf so embedded
# pipes in skill names cannot break the table layout (jq formats them
# escaped via @text, see below).
{
    printf '# Skill Effectiveness — %s\n\n' "$REPORT_ID"
    printf '**Window:** last %s weeks (cutoff %s UTC)\n' \
        "$WEEKS" "$(date -u -d "@${CUTOFF_EPOCH}" -Iseconds 2>/dev/null || echo "${CUTOFF_EPOCH}")"
    printf '**Threshold:** %s (success_rate strictly below this flags the skill)\n' "$THRESHOLD"
    printf '**Sample-size floor:** %s invocations (success+fail+unknown)\n' "$MIN_TOTAL_FOR_FLAG"
    printf '**Total invocations in window:** %s across %s unique skills\n\n' \
        "$TOTAL_INVOCATIONS" "$UNIQUE_SKILLS"

    if [[ "$FLAGGED_COUNT" -eq 0 ]]; then
        printf '## Flagged skills\n\n'
        printf 'No skills below threshold this period.\n\n'
    else
        printf '## Flagged skills (%s)\n\n' "$FLAGGED_COUNT"
        printf '| skill | total | success | fail | unknown | rate |\n'
        printf '|---|---:|---:|---:|---:|---:|\n'
        # rate * 100 | floor / 100 truncates display to 2 decimal places.
        # Flagging logic upstream uses the exact float — display only.
        printf '%s' "$FLAGGED_JSON" | jq -r '
            .[] | "| \(.skill) | \(.total) | \(.success) | \(.fail) | \(.unknown) | \(.rate * 100 | floor / 100) |"
        '
        printf '\n'
    fi

    printf '## Action policy\n\n'
    printf 'These skills are CANDIDATES for manual review. ⟦ user_name ⟧ decides whether to rewrite. NEVER auto-rewrite.\n\n'
    printf 'If ⟦ user_name ⟧ green-lights a rewrite, route through `@prompt-engineer` (skill design) and `@code-critic` (gate). The rewrite path is the same as any other skill change.\n\n'

    printf '## Outcome proxy version\n\n'
    printf 'v1 — derived from `tool_response` of the immediate Skill call. ARCA-DEBT-004 tracks the v2 upgrade (60-second post-skill correlation window).\n'
} > "$REPORT_FILE" 2>/dev/null || {
    echo "[/skill-effectiveness] ENTORNO: cannot write $REPORT_FILE." >&2
    exit 2
}

# Stats: one effectiveness_runs bump per invocation, weeks_processed
# bump because we wrote a report, flagged_skills_total cumulative, and
# unique_skills bumps once per skill in the current window. Semantics
# is "distinct-skills-per-window summed across runs", NOT lifetime
# unique skills (10 weekly runs over the same 20 skills accumulate 200,
# not 20). Counter races with sibling helpers — same trade-off
# ARCA-DEBT-001 documents (5-way now). See ARCA-DEBT-005 if a true
# lifetime-unique counter is later required.
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-${PWD}}"
STATS_HELPER="${PROJECT_DIR}/hooks/lib/skill-telemetry-stats.sh"
if [[ -x "$STATS_HELPER" ]]; then
    bash "$STATS_HELPER" effectiveness_runs 2>/dev/null || true
    bash "$STATS_HELPER" weeks_processed 2>/dev/null || true
    if [[ "$FLAGGED_COUNT" -gt 0 ]]; then
        i=0
        while (( i < FLAGGED_COUNT )); do
            bash "$STATS_HELPER" flagged_skills_total 2>/dev/null || true
            i=$((i + 1))
        done
    fi
    if [[ "$UNIQUE_SKILLS" -gt 0 ]]; then
        i=0
        while (( i < UNIQUE_SKILLS )); do
            bash "$STATS_HELPER" unique_skills 2>/dev/null || true
            i=$((i + 1))
        done
    fi
fi

echo "[/skill-effectiveness] Report: ${REPORT_FILE}"
echo "  weeks=${WEEKS} threshold=${THRESHOLD} flagged=${FLAGGED_COUNT} unique_skills=${UNIQUE_SKILLS}"
exit 0
