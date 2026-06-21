#!/usr/bin/env bash
# Hook: scheduled-git-deny
# Trigger: PreToolUse (matcher: Bash)
# Purpose: Block destructive git operations when running under a scheduled
#          (non-interactive) ARCA session, where there is no human to approve.
#
# CONTEXT (incident 2026-05-01):
#   The arca-meta-review.timer ran arca-scheduled-run with
#   --permission-mode bypassPermissions. With no human in the loop and all
#   project hooks bypassed, Claude resolved a push conflict by force-pushing
#   a bad merge (f34ce6f) followed by a chore-sync (32d1bec) that re-added
#   89 deleted files without updating settings.json. Net effect: 22 files
#   reverted to pre-fusion state, 17 hooks unregistered, 3 zombie agents
#   reintroduced. Recovery took 4 hours of interactive session.
#
# DETECTION:
#   The wrapper ~/.local/bin/arca-scheduled-run exports
#   ARCA_SCHEDULED=1 before invoking claude. This hook reads that env var
#   to gate destructive ops only in scheduled context, leaving interactive
#   sessions unaffected.
#
# DENIED OPERATIONS (matched against tool_input.command):
#   - git push  (any form, including push --force, push HEAD:main, etc.)
#   - git merge (any form)
#   - git rebase
#   - git reset --hard / --keep
#   - git commit --amend
#   - git branch -D / git branch --delete
#   - git tag -d / git tag --delete
#   - git reflog expire / gc --prune=now
#
# ALLOWED OPERATIONS (regular meta-review work):
#   - git status, diff, log, show, branch (list), tag (list)
#   - git add, git commit (without --amend) — fast-forward only territory
#   - git stash / stash pop (local, reversible)
#
# EXIT CODES:
#   0 — allow execution (not scheduled, or command not destructive)
#   2 — block (message in stderr is shown to Claude)
#
# AUDIT:
#   Every block is logged to ~/.claude/logs/scheduled-git-deny.jsonl with
#   timestamp, command, and CWD.

set -uo pipefail

# Pass through if not in scheduled context — interactive sessions unaffected.
if [[ "${ARCA_SCHEDULED:-0}" != "1" ]]; then
    exit 0
fi

LOG_DIR="${HOME}/.claude/logs"
LOG_FILE="${LOG_DIR}/scheduled-git-deny.jsonl"
mkdir -p "${LOG_DIR}" 2>/dev/null || true

# Need jq to parse hook input. Fail open on missing jq — hook should never
# break the runtime, only add a guardrail.
if ! command -v jq >/dev/null 2>&1; then
    exit 0
fi

INPUT=$(cat 2>/dev/null || echo '{}')
TOOL_NAME=$(printf '%s' "${INPUT}" | jq -r '.tool_name // empty' 2>/dev/null || echo "")
COMMAND=$(printf '%s' "${INPUT}" | jq -r '.tool_input.command // empty' 2>/dev/null || echo "")
CWD=$(printf '%s' "${INPUT}" | jq -r '.cwd // empty' 2>/dev/null || echo "${PWD:-}")

[[ "${TOOL_NAME}" != "Bash" ]] && exit 0
[[ -z "${COMMAND}" ]] && exit 0

# Detect destructive git operations using shell tokenization. Avoids the
# false-positive class where 'echo "how to git push"' was previously
# treated as a real push because regex matched the substring inside the
# quoted argument.
is_destructive_git() {
    local cmd="$1"
    python3 - "$cmd" <<'PY'
import shlex
import sys

cmd = sys.argv[1]

# shlex.split drops quotes, so tokens reflect the real argv that bash would
# receive. If parsing fails (unbalanced quotes, complex heredoc) fall back
# to a raw substring check — fail-closed for safety in scheduled context.
try:
    tokens = shlex.split(cmd, comments=True, posix=True)
except ValueError:
    fallback_markers = ("git push", "git merge", "git rebase",
                        "git reset --hard", "git commit --amend")
    sys.exit(0 if any(m in cmd for m in fallback_markers) else 1)

SEPARATORS = {"&&", "||", "|", ";"}

i = 0
n = len(tokens)
while i < n:
    t = tokens[i]
    is_command_start = (i == 0) or (tokens[i - 1] in SEPARATORS)
    if not is_command_start or t != "git":
        i += 1
        continue

    # Skip optional `-C <path>` directive that precedes the subcommand.
    j = i + 1
    if j < n and tokens[j] == "-C" and (j + 1) < n:
        j += 2

    if j >= n:
        break
    sub = tokens[j]
    rest = tokens[j + 1:]

    if sub in {"push", "merge", "rebase"}:
        sys.exit(0)
    if sub == "reset" and any(r in {"--hard", "--keep"} for r in rest):
        sys.exit(0)
    if sub == "commit" and "--amend" in rest:
        sys.exit(0)
    if sub == "branch" and any(r in {"-D", "--delete"} for r in rest):
        sys.exit(0)
    if sub == "tag" and any(r in {"-d", "--delete"} for r in rest):
        sys.exit(0)
    if sub == "reflog" and rest and rest[0] == "expire":
        sys.exit(0)
    if sub == "gc" and "--prune=now" in rest:
        sys.exit(0)

    i = j + 1

sys.exit(1)
PY
}

if ! is_destructive_git "${COMMAND}"; then
    exit 0
fi

# Log the block (best-effort, never blocks on log failure).
{
    jq -nc \
        --arg ts "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
        --arg type "scheduled_git_block" \
        --arg command "${COMMAND}" \
        --arg cwd "${CWD}" \
        '{ts:$ts, type:$type, command:$command, cwd:$cwd}' \
        >> "${LOG_FILE}"
} 2>/dev/null || true

# Emit the message Claude sees in the scheduled session.
cat >&2 <<'BLOCK_MSG'
[SCHEDULED-GIT-DENY] BLOCKED.

This claude session is running under arca-scheduled-run (ARCA_SCHEDULED=1).
Destructive git operations are denied without an interactive human gate.

Allowed in scheduled context:
  - read-only ops: status, diff, log, show, branch (list), tag (list)
  - git add, git commit (no --amend), git stash / stash pop

Denied here (this command):
  - git push / merge / rebase / reset --hard / commit --amend
  - git branch -D / tag -d / reflog expire / gc --prune=now

Resolution paths:
  1. Skip the operation. The schedule should produce artefacts only
     (briefings/, docs/), not history-mutating git ops.
  2. Defer to interactive session. ⟦ user_name ⟧ reviews and runs the git
     operation manually or via @git-master with full gates.
  3. If absolutely necessary, the scheduled run can append a TODO to
     briefings/<name>.md describing what should be pushed/merged.

Audit trail: ~/.claude/logs/scheduled-git-deny.jsonl
Incident reference: ADR-013 (post-merge f34ce6f recovery, 2026-05-01).
BLOCK_MSG

exit 2
