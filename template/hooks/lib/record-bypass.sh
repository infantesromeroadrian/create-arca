#!/usr/bin/env bash
# hooks/lib/record-bypass.sh — sourceable helper for ADR-045 bypass telemetry.
#
# Defines `record_bypass()`. Called by the orchestrator after every admin
# bypass merge to maintain three artefacts in lockstep:
#   1) ~/.claude/state/comprehension-gate-bypasses.log (prose, append-only)
#   2) ~/.claude/state/comprehension-gate-bypasses.jsonl (structured, NEW)
#   3) ~/.claude/state/bypass-telemetry.json (aggregate stats, atomic update)
#
# All three writes are best-effort: if any one fails, the others are still
# attempted. The function never aborts the calling shell on partial failure.
#
# Usage:
#   source "$REPO/hooks/lib/record-bypass.sh"
#   record_bypass <pr_num> <sha> <branch> "<reason>" ["<reason_short>"]
#
# `reason_short` is optional; defaults to "uncategorized" if absent. Use a
# stable short label (kebab-case) for aggregation — e.g., "ci-pre-existing",
# "writeup-only", "rollback-urgent".

# Reason-short auto-derivation when not provided. Maps common prose patterns
# to stable kebab-case labels for the by_reason_short stats bucket.
_record_bypass_derive_reason_short() {
    local reason="$1"
    # Order matters: more-specific writeup signature first because writeup
    # bypass entries embed the same "pre-existing CI fails" justification
    # text. Match writeup before falling through to ci-pre-existing.
    case "$reason" in
        *"writeup-only"*|*"writeup paso"*) echo "writeup-only" ;;
        *"rollback"*) echo "rollback-urgent" ;;
        *"force push"*) echo "force-push" ;;
        *"pre-existing CI fails"*|*"pre-existing"*) echo "ci-pre-existing" ;;
        *) echo "uncategorized" ;;
    esac
}

# ISO week number compatible with `by_week` bucket keys.
_record_bypass_iso_week() {
    date -u +"%G-W%V"
}

record_bypass() {
    local pr="${1:-}"
    local sha="${2:-}"
    local branch="${3:-}"
    local reason="${4:-}"
    local reason_short="${5:-}"

    if [[ -z "$pr" || -z "$sha" || -z "$branch" || -z "$reason" ]]; then
        printf 'record_bypass: missing required arg (pr/sha/branch/reason)\n' >&2
        return 1
    fi

    [[ -z "$reason_short" ]] && reason_short="$(_record_bypass_derive_reason_short "$reason")"

    local state_dir="${HOME}/.claude/state"
    mkdir -p "$state_dir" 2>/dev/null || true

    local prose_log="${state_dir}/comprehension-gate-bypasses.log"
    local jsonl_log="${state_dir}/comprehension-gate-bypasses.jsonl"
    local stats="${state_dir}/bypass-telemetry.json"

    local ts; ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    local week; week="$(_record_bypass_iso_week)"

    # 1) Append to prose log (preserves the existing format).
    printf '%s | PR #%s | BYPASS_GATE=1 ARCA_DIFF_BYPASS=1 | squash+admin | %s→main | SHA=%s | authorized: ⟦ user_name ⟧ | reason: %s | %s\n' \
        "$ts" "$pr" "$branch" "$sha" "$reason" "$reason_short" >> "$prose_log" 2>/dev/null || true

    # 2) Append JSONL record (structured).
    if command -v jq >/dev/null 2>&1; then
        jq -nc \
            --arg ts "$ts" \
            --argjson pr "$pr" \
            --arg sha "$sha" \
            --arg branch "$branch" \
            --arg reason "$reason" \
            --arg reason_short "$reason_short" \
            --arg week "$week" \
            --arg operator "⟦ user_name ⟧" \
            '{ts:$ts, pr:$pr, sha:$sha, branch:$branch, reason:$reason,
              reason_short:$reason_short, week:$week, operator:$operator}' \
            >> "$jsonl_log" 2>/dev/null || true
    fi

    # 3) Update aggregate stats atomically. P0-H2 fix (audit 2026-05-16):
    # the previous tmp+mv pattern was atomic per-write but concurrent
    # invocations could still interleave (one reads stale state while
    # another writes). flock serializes the read-modify-write window.
    if command -v jq >/dev/null 2>&1; then
        local record
        record="$(jq -nc \
            --arg ts "$ts" \
            --argjson pr "$pr" \
            --arg sha "$sha" \
            --arg week "$week" \
            --arg reason_short "$reason_short" \
            '{ts:$ts, pr:$pr, sha:$sha, week:$week, reason_short:$reason_short}')"

        (
            flock -w 5 9 || exit 1
            local tmp="${stats}.tmp.$$"
            if [[ -f "$stats" ]]; then
                jq --arg week "$week" \
                   --arg rs "$reason_short" \
                   --arg ts "$ts" \
                   --argjson record "$record" \
                   '.total_bypasses = (.total_bypasses // 0) + 1
                    | .by_week[$week] = ((.by_week[$week] // 0) + 1)
                    | .by_reason_short[$rs] = ((.by_reason_short[$rs] // 0) + 1)
                    | .last_5 = ((.last_5 // []) + [$record])[-5:]
                    | .last_seen = $ts
                    | .first_seen = (.first_seen // $ts)' \
                    "$stats" >"$tmp" 2>/dev/null \
                    && mv "$tmp" "$stats" \
                    || rm -f "$tmp"
            else
                jq -n \
                    --arg week "$week" \
                    --arg rs "$reason_short" \
                    --arg ts "$ts" \
                    --argjson record "$record" \
                    '{total_bypasses:1,
                      by_week:{($week):1},
                      by_reason_short:{($rs):1},
                      last_5:[$record],
                      first_seen:$ts,
                      last_seen:$ts}' >"$stats" 2>/dev/null || true
            fi
        ) 9>"${stats}.lock"
    fi

    return 0
}

# Export so subshells can use it when desired.
export -f record_bypass 2>/dev/null || true
export -f _record_bypass_derive_reason_short 2>/dev/null || true
export -f _record_bypass_iso_week 2>/dev/null || true
