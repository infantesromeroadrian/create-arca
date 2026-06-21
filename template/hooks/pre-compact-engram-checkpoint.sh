#!/bin/bash
# ARCA — PreCompact event hook (Claude Code 2.1.105+)
#
# Triggered just before the runtime compacts the conversation. Pushes a
# minimal session snapshot to Engram so context survives compaction. If
# Engram CLI is not on PATH, exits 0 silently — never blocks compaction
# (return {"decision":"block"} would force a hard block, which we do not
# want here; we only want a checkpoint).
#
# Why this exists:
#   ARCA sessions routinely compact mid-task. Recovering "what was being
#   done" required reading the post-compaction summary by hand. With
#   this hook, the active project + git ref + last 200 chars of cwd
#   land in Engram automatically every time.

set -uo pipefail

# P1-H3 fix (audit 2026-05-16): per ADR-058 ⟦ host_os ⟧ migration, engram
# CLI lives in ~/go/bin which is NOT in the inherited PATH for hook
# subprocesses. Export it explicitly so `command -v engram` resolves.
export PATH="${HOME}/go/bin:/usr/local/bin:${PATH}"

ENGRAM_BIN="${ENGRAM_BIN:-engram}"
LOG="${HOME}/.claude/state/pre-compact-checkpoint.log"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || true

if ! command -v "$ENGRAM_BIN" >/dev/null 2>&1; then
    echo "$(date -Iseconds) | engram CLI absent — checkpoint skipped" >> "$LOG"
    exit 0
fi

cwd="${PWD:-unknown}"
project="$(basename "$cwd" 2>/dev/null || echo unknown)"
branch="$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null || echo no-git)"
sha="$(git -C "$cwd" rev-parse --short HEAD 2>/dev/null || echo no-sha)"
head_subject="$(git -C "$cwd" log -1 --pretty='%s' 2>/dev/null || echo no-log)"

note="pre-compact-checkpoint | project=${project} branch=${branch}@${sha} | head=${head_subject:0:120}"

# Best-effort save; never block.
# engram save <title> <content> [--topic TOPIC_KEY]
"$ENGRAM_BIN" save \
    "pre-compact-checkpoint" \
    "$note" \
    --topic session_recovery \
    >>"$LOG" 2>&1 || true

echo "$(date -Iseconds) | OK | $note" >> "$LOG"
exit 0
