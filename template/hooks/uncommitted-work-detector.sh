#!/bin/bash
set -euo pipefail

# PostToolUse hook — Detects extended work without commits
# Suggests saving progress after significant uncommitted changes

STATE_DIR="${HOME}/.claude/state"
COUNTER_FILE="${STATE_DIR}/tool_use_counter.json"
THRESHOLD=15

mkdir -p "$STATE_DIR"

# Read hook input
INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)

# Only count write-type operations
case "$TOOL_NAME" in
    Edit|Write|MultiEdit|Bash) ;;
    *) exit 0 ;;
esac

# Initialize or load counter
if [ -f "$COUNTER_FILE" ]; then
    STORED_SESSION=$(jq -r '.session // empty' "$COUNTER_FILE" 2>/dev/null)
    if [ "$STORED_SESSION" != "$SESSION_ID" ]; then
        echo '{}' | jq --arg s "$SESSION_ID" '{session: $s, count: 0, alerted_at: 0}' > "$COUNTER_FILE"
    fi
else
    echo '{}' | jq --arg s "$SESSION_ID" '{session: $s, count: 0, alerted_at: 0}' > "$COUNTER_FILE"
fi

# Increment
CURRENT=$(jq -r '.count // 0' "$COUNTER_FILE" 2>/dev/null)
ALERTED_AT=$(jq -r '.alerted_at // 0' "$COUNTER_FILE" 2>/dev/null)
NEW_COUNT=$((CURRENT + 1))
jq --argjson c "$NEW_COUNT" '.count = $c' "$COUNTER_FILE" > "${COUNTER_FILE}.tmp" \
    && mv "${COUNTER_FILE}.tmp" "$COUNTER_FILE"

# Check if we're inside a git repo
if ! git rev-parse --is-inside-work-tree &>/dev/null; then
    exit 0
fi

# Only alert every THRESHOLD operations and if there are actual uncommitted changes
if [ "$NEW_COUNT" -ge "$THRESHOLD" ] && [ $((NEW_COUNT - ALERTED_AT)) -ge "$THRESHOLD" ]; then
    DIRTY=$(git status --porcelain 2>/dev/null | wc -l)
    if [ "$DIRTY" -gt 0 ]; then
        # Update alerted_at to avoid spamming
        jq --argjson a "$NEW_COUNT" '.alerted_at = $a' "$COUNTER_FILE" > "${COUNTER_FILE}.tmp" \
            && mv "${COUNTER_FILE}.tmp" "$COUNTER_FILE"

        echo "${NEW_COUNT} operaciones de escritura, ${DIRTY} archivos sin commit. Considera guardar progreso." >&2
    fi
fi

exit 0
