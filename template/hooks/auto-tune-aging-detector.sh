#!/usr/bin/env bash
# ARCA — auto-tune-aging-detector (SessionStart hook)
#
# Implements ADR-041 (Auto-tune loop closure — SLA + aging detector + review skill).
#
# Reads ~/.claude/state/critic_rejections.json, computes days each
# auto_tune_pending agent has been waiting (using the pending_since
# timestamp written by critic-feedback-tracker.sh), and emits a banner
# section with severity-tiered aging warnings:
#
#   days < SLA            → ordinary banner (handled elsewhere, this hook
#                            stays silent for these agents)
#   SLA <= days < 2*SLA   → [AUTO-TUNE WARN] line per agent
#   days >= 2*SLA         → [AUTO-TUNE CRITICAL] line per agent
#
# Override / config:
#   ARCA_AUTOTUNE_AGING_DISABLE=1  — skip entirely.
#   ARCA_AUTOTUNE_SLA_DAYS=N       — override SLA (default 7).
#
# Stats persisted at ~/.claude/state/auto-tune-aging-stats.json with
# counters {warn_emitted, critical_emitted, bypass}.
#
# Exit code: always 0. SessionStart hooks must not block the session.

set -uo pipefail

if [[ "${ARCA_AUTOTUNE_AGING_DISABLE:-0}" == "1" ]]; then
    bump_stats_bypass="${HOME}/.claude/state/auto-tune-aging-stats.json"
    mkdir -p "$(dirname "$bump_stats_bypass")"
    if command -v jq >/dev/null 2>&1; then
        # P0-H2 fix (audit 2026-05-16): atomic stats update via flock.
        (
            flock -w 5 9 || exit 1
            if [[ -f "$bump_stats_bypass" ]]; then
                tmp="${bump_stats_bypass}.tmp.$$"
                jq '.bypass = (.bypass // 0) + 1' "$bump_stats_bypass" >"$tmp" 2>/dev/null \
                    && mv "$tmp" "$bump_stats_bypass" \
                    || rm -f "$tmp"
            else
                printf '{"warn_emitted":0,"critical_emitted":0,"bypass":1}\n' >"$bump_stats_bypass"
            fi
        ) 9>"${bump_stats_bypass}.lock"
    fi
    exit 0
fi

STATE_FILE="${HOME}/.claude/state/critic_rejections.json"
STATS_FILE="${HOME}/.claude/state/auto-tune-aging-stats.json"
SLA_DAYS="${ARCA_AUTOTUNE_SLA_DAYS:-7}"

if [[ ! -f "$STATE_FILE" ]]; then
    exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
    exit 0
fi

mkdir -p "$(dirname "$STATS_FILE")"

# Compute days from ISO 8601 to now. Portable across GNU date and BSD date
# (macOS): we use Python only when available, otherwise fall back to shell.
days_since() {
    local iso="$1"
    [[ -z "$iso" || "$iso" == "null" ]] && { echo "0"; return 0; }
    if command -v python3 >/dev/null 2>&1; then
        python3 - "$iso" <<'PYEOF' 2>/dev/null
import sys
from datetime import datetime, timezone
iso = sys.argv[1]
try:
    if iso.endswith("Z"):
        iso = iso[:-1] + "+00:00"
    t = datetime.fromisoformat(iso)
    if t.tzinfo is None:
        t = t.replace(tzinfo=timezone.utc)
    delta = datetime.now(timezone.utc) - t
    print(int(delta.total_seconds() // 86400))
except Exception:
    print(0)
PYEOF
        return 0
    fi
    # Fallback: assume the timestamp is "today" if python is unavailable.
    echo "0"
}

warn_count=0
critical_count=0
warn_lines=()
critical_lines=()

# Iterate over auto_tune_pending agents.
while IFS= read -r agent; do
    [[ -z "$agent" ]] && continue
    pending_since=$(jq -r --arg a "$agent" '.pending_since[$a] // ""' "$STATE_FILE" 2>/dev/null)
    rejections=$(jq -r --arg a "$agent" '.rejections[$a] // 0' "$STATE_FILE" 2>/dev/null)
    days=$(days_since "$pending_since")
    # Skip if we cannot compute aging (no timestamp + no python fallback).
    [[ -z "$days" ]] && continue
    if [[ "$days" -ge $((SLA_DAYS * 2)) ]]; then
        critical_lines+=("[AUTO-TUNE CRITICAL] @${agent} pending ${days}d (rejections=${rejections}, SLA ${SLA_DAYS}d × 2 exceeded) → /auto-tune-review ${agent}")
        critical_count=$((critical_count + 1))
    elif [[ "$days" -ge "$SLA_DAYS" ]]; then
        warn_lines+=("[AUTO-TUNE WARN] @${agent} pending ${days}d (rejections=${rejections}, SLA ${SLA_DAYS}d) → /auto-tune-review ${agent}")
        warn_count=$((warn_count + 1))
    fi
done < <(jq -r '.auto_tune_pending[]?' "$STATE_FILE" 2>/dev/null)

if [[ "${#critical_lines[@]}" -gt 0 ]]; then
    for line in "${critical_lines[@]}"; do
        printf '%s\n' "$line"
    done
fi
if [[ "${#warn_lines[@]}" -gt 0 ]]; then
    for line in "${warn_lines[@]}"; do
        printf '%s\n' "$line"
    done
fi

# Update stats. P0-H2 fix (audit 2026-05-16): atomic via flock.
(
    flock -w 5 9 || exit 1
    if [[ -f "$STATS_FILE" ]]; then
        tmp="${STATS_FILE}.tmp.$$"
        jq --argjson w "$warn_count" --argjson c "$critical_count" \
            '.warn_emitted = (.warn_emitted // 0) + $w
             | .critical_emitted = (.critical_emitted // 0) + $c' \
            "$STATS_FILE" >"$tmp" 2>/dev/null \
            && mv "$tmp" "$STATS_FILE" \
            || rm -f "$tmp"
    else
        printf '{"warn_emitted":%d,"critical_emitted":%d,"bypass":0}\n' \
            "$warn_count" "$critical_count" >"$STATS_FILE"
    fi
) 9>"${STATS_FILE}.lock"

exit 0
