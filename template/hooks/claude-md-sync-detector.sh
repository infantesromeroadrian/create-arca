#!/bin/bash
# ARCA — CLAUDE.md global vs project sync detector (PostToolUse:Edit/Write)
#
# ⟦ user_name ⟧ keeps two synchronized copies of CLAUDE.md inside the
# .claude project specifically:
#   1. ~/.claude/CLAUDE.md            (global default for every Claude Code session)
#   2. <.claude>/CLAUDE.md  (project override, currently identical)
#
# When either is edited, the other must be updated by hand or the two
# drift. Drift is silent until something downstream notices ("but I
# already added that rule" → no, only in the global). This hook fires
# after Edit/Write on either copy and surfaces a one-line stderr
# warning with the exact `cp` command needed to resync.
#
# Scope (ARCA-specific):
#   The drift invariant "global == project" only holds for .claude.
#   Any other project (Kaggle, HTB, ArchLinuxConfig, ⟦ org_name ⟧, etc.) maintains
#   its own project-scoped CLAUDE.md that is INTENTIONALLY different from
#   the ARCA global. Without the scope check below, every CLAUDE.md edit in
#   any non-ARCA project would emit a spurious DRIFT warning telling ⟦ user_name ⟧
#   to overwrite the other project's CLAUDE.md with the ARCA global. This
#   is the false positive class closed by task #37.
#
# Behavior:
#   - PostToolUse hook: never blocks (exit 0 always).
#   - Stderr lines are surfaced by the runtime as part of the tool
#     output, so Claude (and ⟦ user_name ⟧) see them immediately.
#   - No-op if either file is missing — first-time setup is not drift.
#   - No-op if file_path is neither of the two paths.
#   - No-op if the active project is not .claude (this is what
#     #37 adds — see the `is_ares_project` guard below).

set -uo pipefail

# Mandatory dependency. Bail silently if absent.
command -v jq >/dev/null 2>&1 || exit 0

GLOBAL="${HOME}/.claude/CLAUDE.md"
# CLAUDE_PROJECT_DIR is set by the runtime when the hook fires within
# a project. Fall back to PWD if unset (loose detection).
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-${PWD}}"
PROJECT="${PROJECT_DIR}/CLAUDE.md"

INPUT=$(cat)
file_path=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || echo "")
[[ -z "$file_path" ]] && exit 0

# Resolve to absolute path for comparison. The runtime already passes
# absolute paths but defensive realpath handles relative cases.
abs_path=$(realpath -m "$file_path" 2>/dev/null || echo "$file_path")

# Only fire on writes to one of the two CLAUDE.md copies.
if [[ "$abs_path" != "$GLOBAL" && "$abs_path" != "$PROJECT" ]]; then
    exit 0
fi

# Scope guard — only enforce the global==project invariant when the
# active project is .claude. Detection layers, fast-to-slow:
#   1. PROJECT_DIR basename equals ".claude" (covers the canon).
#   2. git remote origin URL contains ".claude" (covers worktrees
#      of the repo that may be checked out under a different basename).
# If neither matches, the drift invariant does not apply and we exit
# silently. Avoids spurious DRIFT warnings on Kaggle / HTB / personal
# projects that maintain their own project-scoped CLAUDE.md.
is_ares_project="false"
if [[ "$(basename "$PROJECT_DIR")" == ".claude" ]]; then
    is_ares_project="true"
elif command -v git >/dev/null 2>&1; then
    remote_url=$(git -C "$PROJECT_DIR" config --get remote.origin.url 2>/dev/null || echo "")
    if [[ "$remote_url" == *".claude"* ]]; then
        is_ares_project="true"
    fi
fi
[[ "$is_ares_project" != "true" ]] && exit 0

# Both files must exist for the comparison to be meaningful. If only
# one exists we are in first-time setup; nothing to warn about.
[[ ! -f "$GLOBAL" ]] && exit 0
[[ ! -f "$PROJECT" ]] && exit 0

# In-sync — silent. The diff exit code is 0 when files match.
if diff -q "$GLOBAL" "$PROJECT" >/dev/null 2>&1; then
    exit 0
fi

# Drift detected. Print which copy was just edited and the one-line
# fix to resync. Direction matters: copy FROM the just-edited file TO
# the other one — the user's most recent intent is the ground truth.
{
    echo "[claude-md-sync] DRIFT: ~/.claude/CLAUDE.md and ${PROJECT} differ."
    if [[ "$abs_path" == "$GLOBAL" ]]; then
        echo "  Just edited: global. Resync project with:"
        echo "    cp \"${GLOBAL}\" \"${PROJECT}\""
    else
        echo "  Just edited: project. Resync global with:"
        echo "    cp \"${PROJECT}\" \"${GLOBAL}\""
    fi
} >&2

exit 0
