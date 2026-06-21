#!/bin/bash
# ARCA — Debug loop detector (PostToolUse:Read|Edit|Write|MultiEdit)
#
# Counts file accesses per session. Surfaces a stderr nudge once a
# single file has been touched 4+ times — common signature of an LLM
# stuck rereading the same surface instead of changing approach.
#
# State file: ~/.claude/state/file_access_counts.json
#   {"session": "<id>", "files": {"<path>": <count>, ...}}
#
# Hardening notes (post-incident 2026-05-03):
#   - The state file got corrupted in production: concurrent
#     PostToolUse invocations on Read/Edit pairs raced on the
#     tmp + mv write path (no flock) and left binary garbage at the
#     head of the file.
#   - When jq read the corrupt file the script died under
#     `set -euo pipefail` with a non-zero exit and ZERO stderr (the
#     `2>/dev/null` on the jq calls swallowed the diagnostic). The
#     Claude Code runtime then emitted
#     "Failed with non-blocking status code: No stderr output"
#     on every Read/Edit/Write/MultiEdit, polluting the user's view.
#
# Three fixes applied below:
#   1. Validate the file with `jq -e .` before reading. On corruption,
#      reset to the empty schema instead of crashing.
#   2. Wrap the read-modify-write in flock so two concurrent
#      PostToolUse invocations cannot interleave the tmp + mv pair.
#   3. Trap any unexpected jq failure to a graceful exit 0 — the hook
#      is observability, not correctness, and must never poison the
#      hook chain even if its own state is broken.

set -uo pipefail

STATE_DIR="${HOME}/.claude/state"
COUNTER_FILE="${STATE_DIR}/file_access_counts.json"
LOCK_FILE="${COUNTER_FILE}.lock"

mkdir -p "$STATE_DIR"

command -v jq >/dev/null 2>&1 || exit 0

INPUT=$(cat)

TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || echo "")
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || echo "")

case "$TOOL_NAME" in
    Read|Edit|Write|MultiEdit) ;;
    *) exit 0 ;;
esac

FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.file // empty' 2>/dev/null || echo "")
[[ -z "$FILE_PATH" ]] && exit 0

# Empty schema used for first-write and corruption recovery.
empty_schema() {
    jq -n --arg s "$SESSION_ID" '{session: $s, files: {}}'
}

# Atomic read-modify-write under flock. fd 9 released on script exit.
exec 9>"$LOCK_FILE"
flock -x 9

# Validation step: if the file is missing OR not parseable as JSON,
# rewrite from scratch. `jq -e .` returns non-zero on parse error or
# null/false top-level — exactly the cases we want to recover from.
needs_reset=0
if [[ ! -f "$COUNTER_FILE" ]]; then
    needs_reset=1
elif ! jq -e . "$COUNTER_FILE" >/dev/null 2>&1; then
    needs_reset=1
else
    STORED_SESSION=$(jq -r '.session // ""' "$COUNTER_FILE" 2>/dev/null || echo "")
    if [[ "$STORED_SESSION" != "$SESSION_ID" ]]; then
        needs_reset=1
    fi
fi

if (( needs_reset == 1 )); then
    if ! empty_schema > "${COUNTER_FILE}.tmp" 2>/dev/null; then
        # jq itself is unhappy. Bail silently — observability, not correctness.
        rm -f "${COUNTER_FILE}.tmp" 2>/dev/null
        exit 0
    fi
    mv "${COUNTER_FILE}.tmp" "$COUNTER_FILE"
fi

# Increment counter for this file. Failures here also bail silently —
# the counter is best-effort.
CURRENT=$(jq -r --arg f "$FILE_PATH" '.files[$f] // 0' "$COUNTER_FILE" 2>/dev/null || echo 0)
[[ "$CURRENT" =~ ^[0-9]+$ ]] || CURRENT=0
NEW_COUNT=$((CURRENT + 1))

if ! jq --arg f "$FILE_PATH" --argjson c "$NEW_COUNT" '.files[$f] = $c' "$COUNTER_FILE" \
     > "${COUNTER_FILE}.tmp" 2>/dev/null; then
    rm -f "${COUNTER_FILE}.tmp" 2>/dev/null
    exit 0
fi
mv "${COUNTER_FILE}.tmp" "$COUNTER_FILE"

# Loop pattern: same file touched 4 times. Surface once, on the
# transition (NEW_COUNT == 4) — not every subsequent access.
if (( NEW_COUNT == 4 )); then
    BASENAME=$(basename "$FILE_PATH")
    LOOP_FILES=$(jq '[.files | to_entries[] | select(.value > 3)] | length' \
        "$COUNTER_FILE" 2>/dev/null || echo 0)

    SUGGESTION="Has accedido a ${BASENAME} ${NEW_COUNT} veces en esta sesion."
    if [[ "$LOOP_FILES" =~ ^[0-9]+$ ]] && (( LOOP_FILES > 1 )); then
        SUGGESTION="${SUGGESTION} ${LOOP_FILES} archivos muestran patron de loop."
    fi
    SUGGESTION="${SUGGESTION} Considera cambiar de enfoque o aislar el problema."

    echo "$SUGGESTION" >&2
fi

exit 0
