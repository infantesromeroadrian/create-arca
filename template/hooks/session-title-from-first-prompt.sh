#!/bin/bash
# ARCA — Session-title-from-first-prompt (Claude Code 2.1.96+)
#
# UserPromptSubmit hook. On the very first prompt of a session, derive
# a short title from the prompt text and emit it via
# hookSpecificOutput.sessionTitle. On subsequent prompts in the same
# session, exits silently — we do not want titles flapping mid-session.
#
# The "first prompt" detection uses a per-session marker file under
# ~/.claude/state/session-titled/<session_id>.

set -uo pipefail

STATE_DIR="${HOME}/.claude/state/session-titled"
mkdir -p "$STATE_DIR" 2>/dev/null || true

input="$(cat 2>/dev/null || true)"
[[ -z "$input" ]] && exit 0

session_id="$(printf '%s' "$input" | jq -r '.session_id // ""' 2>/dev/null)"
prompt="$(printf '%s' "$input" | jq -r '.user_prompt // .prompt // ""' 2>/dev/null)"

[[ -z "$session_id" || -z "$prompt" ]] && exit 0

marker="${STATE_DIR}/${session_id}"
[[ -f "$marker" ]] && exit 0

# Build a short title: first 60 chars, single line, dropped trailing
# whitespace, no leading slash-command, no quotes.
title="$(printf '%s' "$prompt" \
    | head -c 200 \
    | tr '\n' ' ' \
    | sed -E 's/^[[:space:]]+//;s/[[:space:]]+$//' \
    | sed -E 's/^\/[a-z0-9_-]+ //' \
    | sed -E 's/["'\''`]//g' \
    | head -c 60)"

[[ -z "$title" ]] && exit 0

touch "$marker"

jq -nc --arg t "$title" '{
    hookSpecificOutput: {
        hookEventName: "UserPromptSubmit",
        sessionTitle: $t
    }
}'
exit 0
