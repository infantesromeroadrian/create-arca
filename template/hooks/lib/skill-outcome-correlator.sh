#!/usr/bin/env bash
# ARCA — Skill outcome correlator v2 (ARCA-DEBT-004)
#
# Resolves `outcome: "unknown"` events in skill-telemetry.jsonl by correlating
# with global tool-use telemetry within a temporal window.
#
# Why v2 is necessary:
#
#   skill-telemetry.sh (Task #52) emits `outcome: "unknown"` for slash-command
#   invocations because UserPromptSubmit fires BEFORE the slash command body
#   executes — there is no way at fire time to know if the command succeeded.
#   PostToolUse:Skill (the other ingress) emits real outcomes, but slash
#   commands never produce a PostToolUse:Skill event because Claude Code
#   expands the slash body inline.
#
#   The friday-gc smoke-test (2026-05-11) confirmed the operational impact:
#   skip_substitution/pass_conventional = 4.14x in git-commit-validator-stats,
#   but with outcome="unknown" we cannot tell legitimate HEREDOC commits from
#   format-check bypass. This correlator closes that gap with a heuristic that
#   is honest about its limits.
#
# Heuristic (after timestamp canonicalisation to epoch integers):
#
#   For each event with outcome="unknown":
#     1. Find tool_use events in ~/.claude/telemetry.jsonl matching:
#        - same session_id
#        - epoch(ts) in window [skill_epoch + 1, skill_epoch + WINDOW_SECONDS]
#     2. Classify outcome:
#        - 0 tool_use in window           → "abandoned" (operator shifted away)
#        - any Bash with exit_code != 0   → "fail" (failed activity downstream)
#        - >= 1 tool_use, all clean       → "active" (skill catalyzed work)
#
#   "active" is NOT the same as "success" — it only means the skill triggered
#   downstream activity. The original event keeps outcome="unknown" in the
#   source JSONL; resolved events go to a separate append-only file so the
#   audit trail of the raw decision is preserved.
#
#   "fail" classification is sensitive to UNRELATED Bash failures in the same
#   session (e.g. `grep` returning exit 1 because pattern not found). This is
#   a known v2 limitation. v3 should correlate by command-pattern, not exit
#   code alone. Tracked under ARCA-DEBT-004 itself.
#
# Why epoch ints, not ISO-8601 lex compare (ciclo 1 critic B1):
#
#   skill-telemetry.jsonl uses local offset (+00:00 in your local time), global
#   telemetry.jsonl uses Z (UTC). Lex string comparison of mixed-offset
#   timestamps is mathematically wrong — `"...10:30:00Z" > "...12:00:00+00:00"`
#   is FALSE lexicographically but TRUE in real time. The ciclo 1 implementation
#   would have marked ~100% of production events as "abandoned" during Spanish
#   working hours. v2 normalises every timestamp to an epoch int via python3
#   datetime BEFORE comparison.
#
# Race safety (ciclo 1 critic B2):
#
#   The flock is acquired BEFORE the read loop, not just before the cursor
#   write. Two concurrent invocations (e.g. /friday-gc colliding with a
#   morning-briefing cron) serialise via the shared lock — only one walks the
#   JSONL at a time, preventing N× duplication of resolved records.
#
# Outputs:
#
#   ~/.claude/state/skill-telemetry-resolved.jsonl    (append-only)
#
#   Each resolved record carries the original fields plus:
#     - resolved_outcome:    "active" | "fail" | "abandoned"
#     - resolved_at:         ISO-8601 UTC-Z timestamp of the correlation pass
#     - window_seconds:      window size used (default 300 = 5min)
#     - tools_in_window:     integer count of tool_use events observed
#     - failing_bash_count:  integer count of Bash tool_use with exit_code != 0
#
# Idempotency:
#
#   The script tracks the highest ts already processed in
#   ~/.claude/state/skill-outcome-correlator-cursor.txt. Re-runs only process
#   events newer than the cursor. Safe to invoke from cron, /friday-gc,
#   /morning-briefing, or manually.
#
#   Trade-off (ciclo 1 critic A3): out-of-order events arriving after the
#   cursor passes their ts are silently skipped. Acceptable for a post-process
#   correlator over append-only JSONL. Test 11 pins this behaviour explicitly
#   so a future refactor does not change it silently.
#
# Failure modes (fail-open everywhere):
#
#   - jq absent:           exit 0 silently
#   - python3 absent:      exit 0 silently  (added in v2 — critic A4)
#   - source JSONL absent: exit 0 silently
#   - state dir read-only: exit 0 silently  (writability gate up-front)
#   - lock acquisition timeout: exit 0 silently (concurrent run holds the lock,
#                                                this invocation defers)

set -uo pipefail

WINDOW_SECONDS="${ARCA_SKILL_OUTCOME_WINDOW:-300}"

SKILL_JSONL="${HOME}/.claude/state/skill-telemetry.jsonl"
GLOBAL_JSONL="${HOME}/.claude/telemetry.jsonl"
RESOLVED_JSONL="${HOME}/.claude/state/skill-telemetry-resolved.jsonl"
CURSOR_FILE="${HOME}/.claude/state/skill-outcome-correlator-cursor.txt"
STATE_DIR="${HOME}/.claude/state"
LOCK_FILE="${STATE_DIR}/skill-outcome-correlator.lock"

command -v jq      >/dev/null 2>&1 || exit 0
command -v python3 >/dev/null 2>&1 || exit 0   # critic A4 — python3 fail-open
[[ -f "$SKILL_JSONL" ]] || exit 0
[[ -d "$STATE_DIR" && -w "$STATE_DIR" ]] || exit 0

# ----------------------------------------------------------------------------
# Canonicalisation helpers — invoked ONCE up-front to convert the JSONL streams
# into epoch-keyed scratch files. After this point all comparisons are integer
# epoch ints, not ISO-8601 strings (closes ciclo 1 critic B1).
# ----------------------------------------------------------------------------

# Python helper: read JSONL on stdin, emit `<epoch>\t<raw-line>` on stdout for
# every line whose `.ts` parses. Lines with unparseable ts are dropped silently.
#
# Implementation note: uses `python3 -c '...'` rather than heredoc-stdin
# (`python3 - <<EOF`) because the heredoc form reassigns stdin and would
# starve the python process of pipe input. Single-quoted script body keeps
# the shell from expanding `$` references inside the python code.
to_epoch_keyed() {
    python3 -c '
import datetime
import json
import sys

for raw in sys.stdin:
    raw = raw.rstrip("\n")
    if not raw:
        continue
    try:
        rec = json.loads(raw)
        ts = rec.get("ts")
        if not ts:
            continue
        # Normalise the Z-suffix shape that fromisoformat rejects on Python <3.11.
        if ts.endswith("Z"):
            ts_norm = ts[:-1] + "+00:00"
        else:
            ts_norm = ts
        dt = datetime.datetime.fromisoformat(ts_norm)
        if dt.tzinfo is None:
            # No tz info: assume UTC to keep comparisons deterministic.
            dt = dt.replace(tzinfo=datetime.timezone.utc)
        epoch = int(dt.timestamp())
        print(f"{epoch}\t{raw}")
    except (ValueError, TypeError, json.JSONDecodeError):
        continue
'
}

# ----------------------------------------------------------------------------
# Main pass — under exclusive flock so concurrent invocations serialise
# (closes ciclo 1 critic B2). The lock covers BOTH the scan and the cursor
# update; only one process walks the JSONL at a time.
# ----------------------------------------------------------------------------

run_correlation() {
    local verbose="${1:-quiet}"
    local resolved_count=0

    # Build scratch files of (epoch, raw) for both inputs. Skip the global
    # build if its source is missing — every event will land as "abandoned".
    local skill_scratch global_scratch
    skill_scratch="$(mktemp 2>/dev/null)" || return 0
    global_scratch="$(mktemp 2>/dev/null)" || { rm -f "$skill_scratch"; return 0; }

    to_epoch_keyed < "$SKILL_JSONL" > "$skill_scratch" 2>/dev/null

    if [[ -f "$GLOBAL_JSONL" ]]; then
        to_epoch_keyed < "$GLOBAL_JSONL" > "$global_scratch" 2>/dev/null
    fi

    # Read cursor (highest epoch already processed). Empty cursor = process all.
    local cursor_epoch=0
    if [[ -f "$CURSOR_FILE" && -r "$CURSOR_FILE" ]]; then
        local cursor_raw
        cursor_raw="$(cat "$CURSOR_FILE" 2>/dev/null || echo "")"
        # Cursor stored as epoch int (v2). Fall back to 0 on malformed content
        # (which includes legacy ISO-8601 cursors from v1 — they will be
        # re-processed once, then the file becomes a clean epoch from v2 on).
        if [[ "$cursor_raw" =~ ^[0-9]+$ ]]; then
            cursor_epoch="$cursor_raw"
        fi
    fi

    local now_iso new_cursor_epoch="$cursor_epoch"
    now_iso="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    # Walk skill events ordered by ascending epoch.
    while IFS=$'\t' read -r skill_epoch skill_line; do
        [[ -z "$skill_epoch" || -z "$skill_line" ]] && continue
        [[ "$skill_epoch" -le "$cursor_epoch" ]] && continue

        local outcome session
        outcome="$(echo "$skill_line" | jq -r '.outcome // empty' 2>/dev/null)"
        if [[ "$outcome" != "unknown" ]]; then
            # Real outcome preserved — only advance cursor, do not emit.
            [[ "$skill_epoch" -gt "$new_cursor_epoch" ]] && new_cursor_epoch="$skill_epoch"
            continue
        fi

        session="$(echo "$skill_line" | jq -r '.session // empty' 2>/dev/null)"
        local window_end=$((skill_epoch + WINDOW_SECONDS))
        local tools_in_window=0 failing_bash_count=0

        if [[ -n "$session" && -s "$global_scratch" ]]; then
            # awk filters by epoch window + session + tool_use type, then we
            # ask jq to count exit_code != 0 on Bash from the filtered subset.
            local filtered
            filtered="$(awk -F'\t' -v lo="$skill_epoch" -v hi="$window_end" \
                            -v sess="$session" '
                $1 > lo && $1 <= hi {
                    line = $2
                    # Quick session pre-filter via substring before paying jq.
                    if (index(line, sess) > 0) print line
                }
            ' "$global_scratch")"

            if [[ -n "$filtered" ]]; then
                tools_in_window="$(echo "$filtered" | jq -r --arg s "$session" '
                    select(.type == "tool_use" and .session == $s) | 1
                ' 2>/dev/null | wc -l | tr -d ' ')"
                failing_bash_count="$(echo "$filtered" | jq -r --arg s "$session" '
                    select(.type == "tool_use" and .session == $s and .tool == "Bash" and (.exit_code // 0) != 0) | 1
                ' 2>/dev/null | wc -l | tr -d ' ')"
            fi
        fi

        local resolved
        if [[ "${tools_in_window:-0}" -eq 0 ]]; then
            resolved="abandoned"
        elif [[ "${failing_bash_count:-0}" -gt 0 ]]; then
            resolved="fail"
        else
            resolved="active"
        fi

        # Append resolved record. Worst case ~500 bytes — under PIPE_BUF=512
        # (Darwin) and PIPE_BUF=4096 (Linux), so a single >> redirect is atomic
        # PROVIDED concurrent writers stay below their platform's PIPE_BUF.
        # The flock above this function already serialises writers, so this is
        # belt-and-suspenders. If a future enrichment pushes the line over 512
        # bytes on Darwin, test_14_resolved_record_under_pipe_buf_darwin fails.
        echo "$skill_line" | jq -c \
            --arg ro "$resolved" \
            --arg ra "$now_iso" \
            --argjson ws "$WINDOW_SECONDS" \
            --argjson tw "$tools_in_window" \
            --argjson fb "$failing_bash_count" \
            '. + {resolved_outcome: $ro, resolved_at: $ra, window_seconds: $ws, tools_in_window: $tw, failing_bash_count: $fb}' \
            >> "$RESOLVED_JSONL" 2>/dev/null

        resolved_count=$((resolved_count + 1))
        [[ "$skill_epoch" -gt "$new_cursor_epoch" ]] && new_cursor_epoch="$skill_epoch"
    done < <(sort -n -k1,1 "$skill_scratch")

    if [[ "$new_cursor_epoch" -gt "$cursor_epoch" ]]; then
        echo "$new_cursor_epoch" > "${CURSOR_FILE}.tmp.$$" 2>/dev/null \
            && mv "${CURSOR_FILE}.tmp.$$" "$CURSOR_FILE" 2>/dev/null
    fi

    rm -f "$skill_scratch" "$global_scratch"

    if [[ "$verbose" == "verbose" ]]; then
        echo "[skill-outcome-correlator] resolved $resolved_count event(s) this pass" >&2
        echo "[skill-outcome-correlator] cursor at epoch $new_cursor_epoch" >&2
    fi
}

# Acquire exclusive lock for the entire correlation pass (ciclo 1 critic B2).
# `-n` makes the lock non-blocking — if another process already holds it, we
# exit 0 silently rather than queue (we run on schedule anyway, no urgency).
verbose_flag="quiet"
[[ "${1:-}" == "--verbose" ]] && verbose_flag="verbose"

(
    flock -n 9 || exit 0
    run_correlation "$verbose_flag"
) 9>"$LOCK_FILE"

exit 0
