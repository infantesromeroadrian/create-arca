#!/bin/bash
# ARCA — telemetry rotation helper (closes issue #33)
#
# Single point of truth for trimming append-only JSONL log files used as
# telemetry. Replaces three inline `tail -5000` blocks that previously
# lived in log-activity.sh, command_logger.sh, and agent-invocation-logger.sh.
# Those copies raced each other: any of the three could truncate while the
# other two were appending, dropping events from whoever wrote between
# the read of `wc -l` and the `mv` of the trimmed file.
#
# Usage:
#   bash hooks/lib/telemetry-rotate.sh <log_file> [keep_lines] [max_size_mb]
#
# Defaults: keep_lines=5000, max_size_mb=30.
#
# Trigger conditions (rotate when ANY hits):
#   - file has > 2 * keep_lines lines (pre-fix threshold was hardcoded 10000)
#   - file size > max_size_mb (issue #33 threshold)
#
# The actual trim writes the last `keep_lines` lines back to the file
# atomically: `tail -N > tmp && mv tmp file`. The whole sequence runs
# under flock so concurrent producers wait rather than race.
#
# Exit codes:
#   0 always — telemetry must never break flow. Failures are silent.

set -uo pipefail

LOG_FILE="${1:-}"
KEEP_LINES="${2:-5000}"
MAX_SIZE_MB="${3:-30}"

# No file → nothing to rotate. Caller probably hasn't written its first
# event yet; let the next call handle it.
[[ -z "$LOG_FILE" ]] && exit 0
[[ ! -f "$LOG_FILE" ]] && exit 0

LOCK_FILE="${LOG_FILE}.rotate.lock"
LINE_THRESHOLD=$((KEEP_LINES * 2))
MAX_SIZE_BYTES=$((MAX_SIZE_MB * 1024 * 1024))

# Cheap pre-check before grabbing the lock. If neither trigger is close,
# skip the lock acquisition — keeps the common case at one stat call.
current_lines=$(wc -l < "$LOG_FILE" 2>/dev/null || echo 0)
current_bytes=$(stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)

if (( current_lines <= LINE_THRESHOLD )) && (( current_bytes <= MAX_SIZE_BYTES )); then
    exit 0
fi

# At least one trigger crossed. Lock and re-check inside the critical
# section — another producer may have rotated while we were measuring.
{
    flock -x 9

    current_lines=$(wc -l < "$LOG_FILE" 2>/dev/null || echo 0)
    current_bytes=$(stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)

    if (( current_lines <= LINE_THRESHOLD )) && (( current_bytes <= MAX_SIZE_BYTES )); then
        # Someone else rotated already. Done.
        exit 0
    fi

    tmp="${LOG_FILE}.rot.tmp.$$"
    if tail -n "$KEEP_LINES" "$LOG_FILE" > "$tmp" 2>/dev/null; then
        if [[ -s "$tmp" ]]; then
            mv "$tmp" "$LOG_FILE"
        else
            rm -f "$tmp"
        fi
    else
        rm -f "$tmp"
    fi
} 9>"$LOCK_FILE"

exit 0
