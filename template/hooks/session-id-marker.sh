#!/usr/bin/env bash
# Hook: session-id-marker
# Trigger: UserPromptSubmit
# Purpose: Maintain ~/.claude/state/current-session-id with the active
#          session id so slash-command skills can resolve it deterministically.
#
# WHY this exists:
#   The /justify skill (skills/justify/run.sh) and other state-keyed skills
#   need the current session id to write per-session state files that the
#   PreToolUse hook forced-justification.sh expects to read with the same
#   key. The hook receives session_id directly in its JSON input. The skill
#   does not — it receives only the user's justification text on stdin.
#
#   Previous fallback chain in run.sh:
#     1. $CLAUDE_SESSION_ID env var      ← not exported by the runtime
#     2. ~/.claude/state/current-session-id   ← only present if hand-written
#     3. $(date +%s)                          ← last resort, EPOCH FILENAME
#
#   The third branch was active in practice, producing state files like
#   1777647708.json that the hook (looking for <real-session>.json) never
#   read. Result: every /justify call appeared "consumed already" because
#   the hook stayed pointed at a stale older state file.
#
#   This hook closes the gap by writing the marker on every prompt, so the
#   skill always finds the correct session id via branch 2.
#
# CONTRACT:
#   - Read JSON from stdin: {session_id, prompt, cwd, ...}
#   - Extract .session_id, validate against [A-Za-z0-9_-]+ (path-traversal
#     guard mirrors the one in skills/justify/run.sh).
#   - Atomically write the value to ~/.claude/state/current-session-id.
#   - Always exit 0; this hook MUST NEVER block prompt submission.
#
# CONCURRENCY:
#   The Claude Code runtime serialises UserPromptSubmit hooks per session,
#   so concurrent writes within a single session are not possible. Across
#   sessions the marker is racy by design: whichever prompt fires last
#   wins. Skills that care about which session they belong to should pass
#   the session id through as an argument rather than rely on the marker.
#
# AUDIT:
#   Failures are silent (exit 0) but the previous marker is preserved on
#   any error path so the hook never leaves a corrupt file behind.

set -uo pipefail

STATE_DIR="${HOME}/.claude/state"
MARKER="${STATE_DIR}/current-session-id"

mkdir -p "${STATE_DIR}" 2>/dev/null || exit 0

# jq missing → degrade silently rather than break prompt submission.
if ! command -v jq >/dev/null 2>&1; then
    exit 0
fi

INPUT=$(cat 2>/dev/null || echo '{}')
SESSION_ID=$(printf '%s' "${INPUT}" | jq -r '.session_id // empty' 2>/dev/null || echo "")

# Empty or invalid session id: leave the existing marker untouched.
[[ -z "${SESSION_ID}" ]] && exit 0
[[ ! "${SESSION_ID}" =~ ^[A-Za-z0-9_-]+$ ]] && exit 0

# Atomic write: render to temp file in the same directory then rename.
# Avoids a partial-write race where a slash command reads the marker
# mid-update.
TMP="${MARKER}.tmp.$$"
printf '%s\n' "${SESSION_ID}" > "${TMP}" 2>/dev/null || exit 0
mv "${TMP}" "${MARKER}" 2>/dev/null || rm -f "${TMP}" 2>/dev/null

exit 0
