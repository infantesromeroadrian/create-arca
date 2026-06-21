#!/bin/bash
export PATH="$HOME/go/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
# ARCA — engram-snapshot-on-stop (Stop event)
#
# Syncs Engram memory to the private GitHub repo at session close.
#
# 2026-06-06 rewrite: the old design mirrored .engram/ into a SEPARATE repo
# (~/.../your-snapshots-repo), which got corrupted (bad object HEAD) and
# bloated (190MB of stray *.db, no .gitignore). Retired it. Now ~/.engram IS
# the git repo (origin = github.com/⟦ github_user ⟧/engram-memory) and
# both this hook AND the hourly engram-sync.timer delegate to ONE script:
# ~/.local/bin/engram-git-sync.sh (engram sync --all + commit + push).
# One mechanism, two triggers (hourly + on session close).
#
# Best-effort: never blocks the Stop event. Bypass with ARCA_ENGRAM_SYNC_SKIP=1.
# Audit log: ~/.claude/state/engram-sync.log
set -uo pipefail

LOG="${HOME}/.claude/state/engram-sync.log"
mkdir -p "$(dirname "$LOG")"
ts() { date -u +%Y-%m-%dT%H:%M:%SZ; }

[[ "${ARCA_ENGRAM_SYNC_SKIP:-0}" == "1" ]] && { echo "$(ts) SKIP (ARCA_ENGRAM_SYNC_SKIP=1)" >>"$LOG"; exit 0; }
# ADR-108: skip if any session leak flag is active (secrets masked
# downstream persistence could re-leak via Engram commit log).
if ls "${HOME}/.claude/briefing/"*.leak >/dev/null 2>&1; then
    latest_leak=$(ls -t "${HOME}/.claude/briefing/"*.leak 2>/dev/null | head -1)
    echo "$(ts) SKIP (ADR-108 leak flag active: ${latest_leak##*/})" >>"$LOG"
    exit 0
fi
command -v engram >/dev/null 2>&1 || { echo "$(ts) SKIP (engram CLI not found)" >>"$LOG"; exit 0; }

SYNC="${HOME}/.local/bin/engram-git-sync.sh"
if [[ -x "$SYNC" ]]; then
    if "$SYNC"; then
        echo "$(ts) OK on-stop sync (engram-memory)" >>"$LOG"
    else
        echo "$(ts) WARN on-stop sync failed (committed locally if any; timer will retry)" >>"$LOG"
    fi
else
    echo "$(ts) SKIP (engram-git-sync.sh missing at $SYNC)" >>"$LOG"
fi
exit 0
