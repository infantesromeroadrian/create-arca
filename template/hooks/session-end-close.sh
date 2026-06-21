#!/bin/bash
# ARCA — session-end close nudge (SessionEnd event).
# Adopted by ADR-094 (2026-06-06).
#
# WHY this exists:
#   The Stop hooks (obsidian-session-close.sh + engram-snapshot-on-stop.sh)
#   fire on every *turn* end and are idempotent by design — they already
#   produce 2 of the 3 mandatory session-close artifacts (Obsidian Status.md
#   + Engram snapshot). SessionEnd fires once when the *session* terminates,
#   which is the correct place — and the only correct place — to nudge the 2
#   artifacts NOT covered by Stop:
#     (1) writeup.md — a per-project deliverable, not per-turn.
#     (2) mem_session_summary — the MANDATORY end-of-session Engram summary,
#         which should be flushed once at the end, never on every turn.
#   Firing these on Stop would spam the operator every turn; firing them here
#   fires them exactly once.
#
# WHAT this hook does NOT do:
#   It does NOT duplicate the Stop artifacts (Status.md, engram snapshot).
#   ADR-094 forbidden-pattern check: no duplicate capability.
#
# Behavior:
#   - Reads stdin defensively (session_id is the only field of interest, and
#     even that is optional — the nudge is the same with or without it).
#   - Emits an advisory nudge to stderr for the 2 uncovered close artifacts.
#   - Appends one audit line to ~/.claude/state/session-end-close.log,
#     mirroring the LOG pattern in obsidian-session-close.sh.
#
# INVARIANTS:
#   - ADVISORY ONLY — SessionEnd cannot block. Exit 0 on every path.
#   - set -uo pipefail (NO -e) — match obsidian-session-close.sh; a single
#     failed command must never abort the close.
#   - jq is OPTIONAL here (the payload is minimal). Parse with jq when
#     present, fall back to a sed extraction otherwise.

set -uo pipefail

LOG="${HOME}/.claude/state/session-end-close.log"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || true

INPUT=$(cat 2>/dev/null || echo "")

# session_id is the only field we care about, and only for the audit line.
# jq is optional — fall back to a minimal sed extraction if it is absent so
# the hook stays useful on a machine without jq.
SESSION=""
if command -v jq >/dev/null 2>&1; then
    SESSION=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || echo "")
else
    SESSION=$(printf '%s' "$INPUT" \
        | sed -nE 's/.*"session_id"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/p' \
        | head -n1 || echo "")
fi

# Advisory nudge to stderr — the 2 close artifacts Stop does NOT cover.
# Stderr (not stdout) so it surfaces to the operator without being captured
# as hook output that could alter control flow.
{
    echo "ARCA session-end: before closing, confirm the 2 close artifacts not handled by Stop:"
    echo "  1. writeup.md — create/update the per-project writeup for this session's work."
    echo "  2. mem_session_summary — run it now to flush the compressed Engram summary (<=200 tokens)."
} >&2

ts="$(date -Iseconds 2>/dev/null || echo "unknown")"
echo "${ts} | session='${SESSION:-?}' nudged (writeup + mem_session_summary)" >> "$LOG" 2>/dev/null || true

exit 0
