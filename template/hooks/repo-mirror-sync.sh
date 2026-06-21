#!/usr/bin/env bash
# Hook: repo-mirror-sync
# Trigger: Stop
# Purpose: Mirror the canonical ARCA categories from the repo to ~/.claude/
#          so that interactive sessions always see the latest agent /
#          command / skill / hook / settings.json.
#
# Why this exists:
#   ~/.claude/ is the runtime view that Claude Code consults at session
#   start (loads agents, commands, hooks, settings). The git repo at
#   ~/Desktop/⟦ host_alias ⟧/.claude is the
#   source of truth — every change goes through review, CI, and commit.
#   Until this hook landed there was no automation gluing the two:
#   commits propagated to GitHub but the local mirror stayed pinned to
#   whatever it was last manually rsync'd to.
#
#   The drift was 16 agents / 5 commands / 6 skills / 17 hooks /
#   settings.json on 2026-05-01 — caught only by a manual audit at
#   session end. This hook closes the gap by running rsync on every
#   Stop event so the next session inherits the latest repo state.
#
# What it syncs (one-way, repo → mirror):
#   agents/        commands/       skills/
#   hooks/         settings.json   CLAUDE.md
#
# What it preserves (NEVER touched):
#   ~/.claude/state/      ~/.claude/projects/      ~/.claude/logs/
#   ~/.claude/cache/      ~/.claude/keybindings.json
#   ~/.claude/settings.local.json (per-machine overrides)
#
# Invariants:
#   - Always exits 0. A sync failure must not block session exit.
#   - Logs every drift detected + sync action to
#     ~/.claude/logs/repo-mirror-sync.jsonl (newest line per session).
#   - Idempotent: if there is no drift, the hook is a no-op.
#
# rsync flags:
#   -a     archive mode (preserves perms, mtimes, recursion)
#   --delete  removes files in the mirror that no longer exist in the
#             repo (closes the case where an agent / hook is deleted in
#             a commit; the mirror would otherwise carry a zombie
#             definition forever)
#
# Constraints:
#   - rsync must be present. If missing, log and exit 0.
#   - The hook must NOT run if it cannot identify the repo path. If
#     the calling cwd is outside the ARCA repo, exit silently.

set -uo pipefail
# ADR-108: warn (do NOT skip) if a leak flag is active. This hook syncs
# repo -> ~/.claude configs; it does NOT persist transcripts, so leak
# propagation is impossible. Warning is for audit visibility only.
if ls "${HOME}/.claude/briefing/"*.leak >/dev/null 2>&1; then
    latest_leak=$(ls -t "${HOME}/.claude/briefing/"*.leak 2>/dev/null | head -1)
    echo "[repo-mirror-sync] ADR-108 WARN leak flag active (${latest_leak##*/}) - configs sync proceeds, transcripts not affected" >&2
fi

# Resolve repo root from CLAUDE_PROJECT_DIR (set by Claude Code) or by
# walking up from the current cwd looking for the marker .git directory.
REPO_ROOT="${CLAUDE_PROJECT_DIR:-}"
if [[ -z "$REPO_ROOT" || ! -d "$REPO_ROOT/.git" ]]; then
    candidate="$PWD"
    while [[ "$candidate" != "/" ]]; do
        if [[ -d "$candidate/.git" && -f "$candidate/CLAUDE.md" && -d "$candidate/agents" ]]; then
            REPO_ROOT="$candidate"
            break
        fi
        candidate=$(dirname "$candidate")
    done
fi

[[ -z "$REPO_ROOT" || ! -d "$REPO_ROOT/agents" ]] && exit 0

# Sanity: this hook only fires for the .claude repo (renamed ARCA
# per ADR-048 — see Fase 6 for repo rename). Other projects in the same
# Claude Code workspace must not be mirrored to ~/.claude — that is
# exclusively the ARCA (formerly ARCA) runtime. Header check accepts both
# names during the rename transition window (ADR-048 Fase 1 changed the
# header from ARCA to ARCA on 2026-05-12; without this regex the hook
# would silently exit 0 and stop syncing).
if [[ ! -f "$REPO_ROOT/CLAUDE.md" ]] \
   || ! grep -qE '^# (ARCA|ARCA) v4\.0' "$REPO_ROOT/CLAUDE.md" 2>/dev/null; then
    exit 0
fi

MIRROR="${HOME}/.claude"
LOG_DIR="${MIRROR}/logs"
LOG_FILE="${LOG_DIR}/repo-mirror-sync.jsonl"

mkdir -p "$LOG_DIR" 2>/dev/null || exit 0

if ! command -v rsync >/dev/null 2>&1; then
    {
        printf '{"ts":"%s","type":"skip","reason":"rsync_missing"}\n' \
            "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    } >> "$LOG_FILE" 2>/dev/null || true
    exit 0
fi

# Pre-sync drift count (informational only — we sync regardless).
drift_count=0
for cat in agents commands skills hooks; do
    [[ ! -d "$REPO_ROOT/$cat" ]] && continue
    while IFS= read -r f; do
        rel="${f#$REPO_ROOT/}"
        if ! diff -q "$f" "$MIRROR/$rel" >/dev/null 2>&1; then
            drift_count=$((drift_count + 1))
        fi
    done < <(find "$REPO_ROOT/$cat" -type f \( -name '*.md' -o -name '*.sh' -o -name '*.json' \) 2>/dev/null)
done

# Sync the five canonical surfaces. --delete handles file removal in the
# repo so the mirror does not retain stale entries.
sync_dir() {
    local src="$1"
    local dst="$2"
    [[ ! -d "$src" ]] && return 0
    rsync -a --delete "$src/" "$dst/" 2>/dev/null || true
}

sync_dir "$REPO_ROOT/agents"   "$MIRROR/agents"
sync_dir "$REPO_ROOT/commands" "$MIRROR/commands"
sync_dir "$REPO_ROOT/skills"   "$MIRROR/skills"
sync_dir "$REPO_ROOT/hooks"    "$MIRROR/hooks"

# Top-level files: copy only when content differs to avoid touching
# mtime needlessly. Settings.json must NOT be deleted by accident, so
# guard against an empty source.
#
# Regression guard: settings.json hooks must reference $HOME/.claude/hooks/
# (canonical runtime path). $CLAUDE_PROJECT_DIR/hooks/ is forbidden because
# that variable resolves to the cwd of whatever project is active — when
# ⟦ user_name ⟧ opens Claude Code from any non-.claude directory the
# referenced files do not exist and 29 hooks fail with file-not-found.
# If the repo source carries the forbidden pattern, skip propagation so
# the global runtime keeps the last known-good settings.json.
for f in settings.json CLAUDE.md; do
    src="$REPO_ROOT/$f"
    dst="$MIRROR/$f"
    if [[ ! -s "$src" ]]; then
        continue
    fi

    # Widened regex (audit batch 2 finding 2.4): the original guard
    # only matched the literal `$CLAUDE_PROJECT_DIR/hooks/`. Trivial
    # bypasses included `${CLAUDE_PROJECT_DIR}/hooks/` (with braces),
    # `$CLAUDE_PROJECT_DIR/hook/` (singular `hook`), and any combination.
    # The new ERE matches: optional braces around the var name, and
    # `hook` with optional trailing `s`. Defense-in-depth — ARCA's own
    # tooling never emits the variant forms, but a careless paste from
    # an external example might.
    if [[ "$f" == "settings.json" ]] && grep -qE '\$\{?CLAUDE_PROJECT_DIR\}?/hooks?/' "$src" 2>/dev/null; then
        echo "[repo-mirror-sync] BLOCKED settings.json sync: \$CLAUDE_PROJECT_DIR/hooks/ (or any \${CLAUDE_PROJECT_DIR}/hook?/ variant) found in source. Use \$HOME/.claude/hooks/ instead." >&2
        {
            printf '{"ts":"%s","type":"block","file":"settings.json","reason":"claude_project_dir_hook_ref"}\n' \
                "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
        } >> "$LOG_FILE" 2>/dev/null || true
        continue
    fi

    if ! diff -q "$src" "$dst" >/dev/null 2>&1; then
        cp "$src" "$dst" 2>/dev/null || true
    fi
done

# Audit line.
{
    printf '{"ts":"%s","type":"sync","drift_pre":%d,"repo":"%s"}\n' \
        "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
        "$drift_count" \
        "$(basename "$REPO_ROOT")"
} >> "$LOG_FILE" 2>/dev/null || true

exit 0
