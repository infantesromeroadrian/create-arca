#!/usr/bin/env bash
# Hook: worktree-isolation-enforcer
# Trigger: PreToolUse (matcher: Bash)
# Purpose: Block git commit/add when the active agent is operating from the
#          main repo instead of its assigned worktree path.
#
# CONTEXT (ticket T15):
#   Three consecutive incidents (commits b26d8b0, 26e011a, aa2427d) occurred
#   when agents with isolation:worktree executed git commit directly on the
#   main repo. No hook blocked the operation. This hook is the mechanical gate
#   preventing reincidence.
#
# DETECTION STRATEGY:
#   The Claude Code hook input JSON includes a `cwd` field (confirmed via
#   hud-state-writer.sh and worktree-create-autogit.sh). It does NOT include
#   agent.isolation — that metadata is not forwarded to PreToolUse:Bash hooks.
#
#   Instead we detect the violation by:
#     1. The command is a git commit or git add operation.
#     2. The cwd does NOT contain /.claude/worktrees/ (i.e., not in a worktree).
#     3. The cwd IS inside a known project root (to avoid false positives on
#        unrelated repos with their own worktrees).
#
#   This is less precise than checking isolation:worktree directly, so we
#   apply a bypass mechanism for legitimate main-repo commits (e.g., post-merge
#   doc fixes, CLAUDE.md updates that explicitly belong on main).
#
# BYPASS:
#   Write any reason string to /tmp/arca-worktree-bypass and the hook will
#   allow the operation once (single-use, atomically consumed).
#   Example:
#     echo "post-merge CLAUDE.md update — main-repo commit intentional" \
#       > /tmp/arca-worktree-bypass
#
# EXIT CODES:
#   0  — allow execution
#   2  — block (message in stderr is shown to Claude)
#
# MODES:
#   Default (ARCA_WORKTREE_ISOLATION_ENFORCE unset or !=1): DRY-RUN.
#     Logs violations to ~/.claude/logs/worktree-isolation-violations.jsonl.
#     Emits a one-line warning to stderr. Returns exit 0.
#   ENFORCE (ARCA_WORKTREE_ISOLATION_ENFORCE=1): hard block with exit 2.
#
# INVARIANTS:
#   - jq required; if missing, logs warning and exits 0 (graceful degrade).
#   - Always exits 0 on parse errors (never block on tool failure).
#   - Violation log: ~/.claude/logs/worktree-isolation-violations.jsonl

set -uo pipefail

# ─── Config ──────────────────────────────────────────────────────────────────
BYPASS_FILE="/tmp/arca-worktree-bypass"
LOG_DIR="${HOME}/.claude/logs"
LOG_FILE="${LOG_DIR}/worktree-isolation-violations.jsonl"
ENFORCE="${ARCA_WORKTREE_ISOLATION_ENFORCE:-0}"

mkdir -p "${LOG_DIR}" 2>/dev/null || true

# ─── Graceful degrade — never break flow if jq missing ───────────────────────
if ! command -v jq >/dev/null 2>&1; then
    echo "[WORKTREE-ISOLATION-ENFORCER] WARNING: jq not found, hook disabled" >&2
    exit 0
fi

# ─── Read and parse hook input ────────────────────────────────────────────────
INPUT=$(cat 2>/dev/null || echo '{}')

TOOL_NAME=$(printf '%s' "${INPUT}" | jq -r '.tool_name // empty' 2>/dev/null || echo "")
COMMAND=$(printf '%s' "${INPUT}" | jq -r '.tool_input.command // empty' 2>/dev/null || echo "")
CWD=$(printf '%s' "${INPUT}" | jq -r '.cwd // empty' 2>/dev/null || echo "${PWD:-}")
SESSION=$(printf '%s' "${INPUT}" | jq -r '.session_id // empty' 2>/dev/null || echo "")

# Only intercept Bash tool
[[ "${TOOL_NAME}" != "Bash" ]] && exit 0

# Only proceed if we have a command to inspect
[[ -z "${COMMAND}" ]] && exit 0

# ─── Filter: only git commit and git add operations ───────────────────────────
# Match patterns:
#   git commit ...
#   git add ...
#   git -C <path> commit ...
#   && git commit ...  (chained commands)
#   ; git commit ...   (sequential commands)
is_git_write_op() {
    local cmd="$1"
    # Use python3 for reliable multiline/token parsing
    python3 -c "
import sys, re

cmd = sys.stdin.read()
# Tokenized check: find any 'git' followed by 'commit' or 'add' (not add-remote, etc.)
# Pattern covers: git commit, git add, git -C ... commit, chained with &&/;/|
pattern = r'(?:^|[;&|]|\s)\s*git(?:\s+-C\s+\S+)?\s+(commit|add)\b'
sys.exit(0 if re.search(pattern, cmd) else 1)
" <<< "${cmd}" 2>/dev/null
}

if ! is_git_write_op "${COMMAND}"; then
    exit 0
fi

# ─── Check: is cwd inside a worktree path? ───────────────────────────────────
# Worktree paths follow the convention: .../.claude/worktrees/agent-<id>/
# If cwd contains that substring, we're in the assigned worktree — OK.
if [[ "${CWD}" == *"/.claude/worktrees/"* ]]; then
    exit 0
fi

# ─── Check: is cwd the main repo (not just any unrelated repo)? ──────────────
# We only enforce on the ARCA project repos to avoid false positives when
# developers commit in unrelated git repos that happen to be open.
# Heuristic: CWD is inside the known projects root or contains ARCA markers.
# The main project roots ⟦ user_name ⟧ works in:
KNOWN_ROOTS=(
    "~/Desktop/⟦ host_alias ⟧/Work"
    "~/Desktop/⟦ host_alias ⟧/Personal"
    "~/Desktop/⟦ host_alias ⟧/HTB"
    "~/Desktop/⟦ host_alias ⟧/Kaggle"
)

in_known_root=0
for root in "${KNOWN_ROOTS[@]}"; do
    if [[ "${CWD}" == "${root}"* ]]; then
        in_known_root=1
        break
    fi
done

# Also enforce if CWD itself contains a .claude directory (ARCA project marker)
if [[ "${in_known_root}" == "0" ]]; then
    if [[ -d "${CWD}/.claude" ]]; then
        in_known_root=1
    fi
fi

# Not in an ARCA-managed project — allow (avoid false positives)
if [[ "${in_known_root}" == "0" ]]; then
    exit 0
fi

# ─── Bypass — single-use, atomically consumed ────────────────────────────────
if [[ -f "${BYPASS_FILE}" ]]; then
    BYPASS_CLAIMED="${BYPASS_FILE}.consumed.$$"
    if mv "${BYPASS_FILE}" "${BYPASS_CLAIMED}" 2>/dev/null; then
        REASON=$(cat "${BYPASS_CLAIMED}" 2>/dev/null || echo "no-reason-given")
        rm -f "${BYPASS_CLAIMED}"
        # Log the bypass event
        {
            jq -nc \
                --arg ts "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
                --arg type "worktree_isolation_bypass" \
                --arg command "${COMMAND}" \
                --arg cwd "${CWD}" \
                --arg session "${SESSION}" \
                --arg reason "${REASON}" \
                '{ts:$ts,type:$type,command:$command,cwd:$cwd,session:$session,reason:$reason}' \
                >> "${LOG_FILE}"
        } 2>/dev/null || true
        echo "[WORKTREE-ISOLATION-ENFORCER] Bypass consumed: ${REASON}" >&2
        exit 0
    fi
    # mv lost race to another concurrent invocation — fall through and evaluate
fi

# ─── Violation detected ───────────────────────────────────────────────────────
TS=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

# Log violation
{
    jq -nc \
        --arg ts "${TS}" \
        --arg type "worktree_isolation_violation" \
        --arg command "${COMMAND}" \
        --arg cwd "${CWD}" \
        --arg session "${SESSION}" \
        --arg mode "$( [[ "${ENFORCE}" == "1" ]] && echo "enforce" || echo "dry-run" )" \
        '{ts:$ts,type:$type,command:$command,cwd:$cwd,session:$session,mode:$mode}' \
        >> "${LOG_FILE}"
} 2>/dev/null || true

if [[ "${ENFORCE}" == "1" ]]; then
    cat >&2 <<EOF
[WORKTREE-ISOLATION-ENFORCER] BLOCK

git write operation detected from main repo path.

  Command : ${COMMAND}
  CWD     : ${CWD}
  Session : ${SESSION:-unknown}

This is a process violation. Agents with isolation:worktree must commit
inside their assigned worktree path (.claude/worktrees/agent-<id>/), NOT
directly on the main repo.

Ticket T15 was raised after three consecutive incidents (b26d8b0,
26e011a, aa2427d) where agents committed directly to main, requiring
post-facto audit. This hook prevents reincidence.

REQUIRED ACTION:
  Verify your cwd is the worktree, not the main repo:
    pwd  # should contain /.claude/worktrees/agent-<id>/
    cd /path/to/.claude/worktrees/agent-<id>/
    git add <files>
    git commit -m "..."

BYPASS (legitimate main-repo commits only — logged):
  echo "reason here" > /tmp/arca-worktree-bypass
  # then retry the git command
EOF
    exit 2
else
    echo "[WORKTREE-ISOLATION-ENFORCER] DRY-RUN: would block git write op from main repo. CWD=${CWD}. Command=${COMMAND:0:60}... Export ARCA_WORKTREE_ISOLATION_ENFORCE=1 to enforce." >&2
    exit 0
fi
