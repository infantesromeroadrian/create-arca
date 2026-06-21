#!/bin/bash
set -euo pipefail

# PostToolUse hook — Detects extended sessions and suggests checkpoints
# Alerts at 50, 100, 150 tool uses with increasing urgency

STATE_DIR="${HOME}/.claude/state"
COUNTER_FILE="${STATE_DIR}/session_tool_total.json"

mkdir -p "$STATE_DIR"

# Read hook input
INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)

# Initialize or load counter
if [ -f "$COUNTER_FILE" ]; then
    STORED_SESSION=$(jq -r '.session // empty' "$COUNTER_FILE" 2>/dev/null)
    if [ "$STORED_SESSION" != "$SESSION_ID" ]; then
        echo '{}' | jq --arg s "$SESSION_ID" --arg t "$(date -Iseconds)" \
            '{session: $s, count: 0, start: $t, checkpoints: []}' > "$COUNTER_FILE"
    fi
else
    echo '{}' | jq --arg s "$SESSION_ID" --arg t "$(date -Iseconds)" \
        '{session: $s, count: 0, start: $t, checkpoints: []}' > "$COUNTER_FILE"
fi

# Increment total tool use counter
CURRENT=$(jq -r '.count // 0' "$COUNTER_FILE" 2>/dev/null)
NEW_COUNT=$((CURRENT + 1))
jq --argjson c "$NEW_COUNT" '.count = $c' "$COUNTER_FILE" > "${COUNTER_FILE}.tmp" \
    && mv "${COUNTER_FILE}.tmp" "$COUNTER_FILE"

# Calculate session duration
START_TIME=$(jq -r '.start // empty' "$COUNTER_FILE" 2>/dev/null)
if [ -n "$START_TIME" ]; then
    START_EPOCH=$(date -d "$START_TIME" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%S" "$START_TIME" +%s 2>/dev/null || echo 0)
    NOW_EPOCH=$(date +%s)
    DURATION_MIN=$(( (NOW_EPOCH - START_EPOCH) / 60 ))
else
    DURATION_MIN=0
fi

# Check checkpoints already triggered
CHECKPOINTS=$(jq -r '.checkpoints | length' "$COUNTER_FILE" 2>/dev/null)

# Alert at milestones (50, 100, 150 tool uses) or time thresholds (120min, 180min)
SHOULD_ALERT=false
REASON=""

if [ "$NEW_COUNT" -eq 50 ] && [ "$CHECKPOINTS" -lt 1 ]; then
    SHOULD_ALERT=true
    REASON="50 tool uses en esta sesion (~${DURATION_MIN}min). Buen momento para un checkpoint."
elif [ "$NEW_COUNT" -eq 100 ] && [ "$CHECKPOINTS" -lt 2 ]; then
    SHOULD_ALERT=true
    REASON="100 tool uses (~${DURATION_MIN}min). Sesion extendida. Considera commit + resumen en Engram."
elif [ "$NEW_COUNT" -eq 150 ] && [ "$CHECKPOINTS" -lt 3 ]; then
    SHOULD_ALERT=true
    REASON="150 tool uses (~${DURATION_MIN}min). Sesion muy larga. Guarda progreso y considera descanso."
elif [ "$DURATION_MIN" -ge 120 ] && [ "$CHECKPOINTS" -lt 1 ]; then
    SHOULD_ALERT=true
    REASON="Llevas ${DURATION_MIN} minutos en esta sesion (${NEW_COUNT} tool uses). Considera un checkpoint."
fi

if [ "$SHOULD_ALERT" = true ]; then
    # Record checkpoint
    jq --arg r "$REASON" '.checkpoints += [$r]' "$COUNTER_FILE" > "${COUNTER_FILE}.tmp" \
        && mv "${COUNTER_FILE}.tmp" "$COUNTER_FILE"

    echo "$REASON" >&2
fi

exit 0
