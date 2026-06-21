#!/bin/bash
# ARCA — Obsidian session-close hook (Stop event).
#
# Closes the gap between CLAUDE.md (which says "every session must
# produce /Projects/<proj>/Status.md") and reality (which never did,
# because nothing automated it).
#
# On every Stop event:
#   - Detect the project name from CWD basename (skips `.claude` and
#     worktree noise).
#   - Capture branch + sha + last commit from git.
#   - Append (or create) `<vault>/Projects/<project>/Status.md` with a
#     single dated session block. Never overwrites — sessions stack.
#
# Fail-open: missing vault, missing git, missing project — exit 0
# silently. The session must always be allowed to close.

set -uo pipefail

VAULT="${ARCA_VAULT:-${HOME}/Desktop/⟦ host_alias ⟧}"
LOG="${HOME}/.claude/state/obsidian-session-close.log"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || true

[[ ! -d "$VAULT" ]] && {
    echo "$(date -Iseconds) | vault absent — skipped" >> "$LOG"
    exit 0
}
# ADR-108: skip Status.md append if any session leak flag is active
# (the session transcript may carry masked-but-identifiable context).
if ls "${HOME}/.claude/briefing/"*.leak >/dev/null 2>&1; then
    latest_leak=$(ls -t "${HOME}/.claude/briefing/"*.leak 2>/dev/null | head -1)
    echo "$(date -Iseconds) | SKIP session-close (ADR-108 leak flag: ${latest_leak##*/})" >> "$LOG"
    exit 0
fi

cwd="${PWD:-}"
project="$(basename "$cwd" 2>/dev/null || echo "")"

# Skip noise: worktree dirs, hidden dirs, root, empty, subagent sessions.
case "$project" in
    ""|"/"|".claude"|"worktrees"|feature-*|fix-*|refactor-*|agent-*|tasks|tmp)
        echo "$(date -Iseconds) | project='$project' skipped (worktree/noise)" >> "$LOG"
        exit 0
        ;;
esac

branch="$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"
sha="$(git -C "$cwd" rev-parse --short HEAD 2>/dev/null || echo "")"
last_commit_subject="$(git -C "$cwd" log -1 --pretty='%s' 2>/dev/null || echo "")"

target_dir="${VAULT}/Projects/${project}"
target_file="${target_dir}/Status.md"

# Only update EXISTING project folders — NEVER create new ones.
# (2026-06-11: this hook used to mkdir a folder per derived session name,
# flooding Projects/ with 54 junk folders — agent-* ids, cwd fragments.
# Project folders are created by humans; the hook only appends to them.)
if [[ ! -d "$target_dir" ]]; then
    echo "$(date -Iseconds) | project='$project' skipped (no existing project folder)" >> "$LOG"
    exit 0
fi

ts="$(date '+%Y-%m-%d %H:%M')"

# First-write seed: full frontmatter + heading.
if [[ ! -f "$target_file" ]]; then
    cat > "$target_file" <<HEADER_EOF
---
type: arca-status
project: ${project}
created: ${ts}
tags: [arca, status, auto-generated]
---

# Status — ${project}

> Auto-appended on every Claude Code session close. Most recent on top.

HEADER_EOF
fi

# Prepend new session block right after the heading (top of log, latest first).
session_block=$(cat <<BLOCK_EOF

## Session ${ts}

- Branch: \`${branch:-?}\` @ \`${sha:-?}\`
- Last commit: ${last_commit_subject:-—}
- CWD: \`${cwd}\`

### Pendientes abiertos
- [ ] (rellenar manualmente o vía Engram digest)

---
BLOCK_EOF
)

# Insert after the "> Auto-appended" line so the freshest block is on top.
tmp="$(mktemp)"
awk -v block="$session_block" '
    /^> Auto-appended on every Claude Code session close/ {
        print
        print block
        next
    }
    { print }
' "$target_file" > "$tmp" && mv "$tmp" "$target_file"

echo "$(date -Iseconds) | wrote ${target_file}" >> "$LOG"

# === Auto-sync to your-vault-repo (best-effort, fail-open) ===
# After writing Status.md to the vault, mirror the ARCA-relevant
# subset to the private versioned repo and push. Hard timeout 30s so
# a slow network never blocks session close. All errors silenced —
# ⟦ user_name ⟧ can always re-run /arca-vault-sync --push manually if this
# misses.
# Resolve repo paths from ARCA_* env (set in arca.fish); fall back to the
# canonical A.R.C.A/ location if the env is unset or stale (e.g. mid-session
# right after the repos were grouped under the A.R.C.A/ mother folder, 2026-06-14).
SYNC_SCRIPT="${ARCA_REPO:-${HOME}/Desktop/⟦ host_alias ⟧/A.R.C.A/.claude}/scripts/arca-vault-sync.sh"
[[ -x "$SYNC_SCRIPT" ]] || SYNC_SCRIPT="${HOME}/Desktop/⟦ host_alias ⟧/A.R.C.A/.claude/scripts/arca-vault-sync.sh"
SYNC_REPO="${ARCA_VAULT_REPO:-${HOME}/Desktop/⟦ host_alias ⟧/A.R.C.A/your-vault-repo}"
[[ -d "${SYNC_REPO}/.git" ]] || SYNC_REPO="${HOME}/Desktop/⟦ host_alias ⟧/A.R.C.A/your-vault-repo"
if [[ -x "$SYNC_SCRIPT" && -d "${SYNC_REPO}/.git" ]] && command -v timeout >/dev/null 2>&1; then
    timeout 30 bash "$SYNC_SCRIPT" --push >>"$LOG" 2>&1 ||         echo "$(date -Iseconds) | arca-vault-sync skipped (timeout/error)" >> "$LOG"
fi

exit 0
