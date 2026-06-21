#!/bin/bash
# ARCA — PR-merge Comprehension Gate v2 (PreToolUse:Bash)
#
# Blocks `gh pr merge <N>` and `git push <remote> main|master` until the
# operator has demonstrated comprehension of the change about to land.
#
# v2 vs v1
# --------
# v1 (PR #18) checked WORD COUNT only. A 40-word Lorem Ipsum body
# satisfied the gate. v2 keeps that as a fallback path but, when run
# in an interactive shell with Ollama reachable, escalates to:
#
#   1. Capture the actual diff (gh pr diff <N> or git diff range).
#   2. Show a snippet to the operator on /dev/tty.
#   3. Start a hard countdown (default 90s, env
#      ARCA_DIFF_COMPREHENSION_TIMEOUT) and read a free-text summary.
#   4. Run an LLM judge (hooks/lib/diff-judge.sh) over (summary, diff)
#      with a 3-verdict rubric: APPROVED | INCOHERENT | TOO_SHALLOW.
#   5. Persist the verdict in ~/.claude/state/diff-comprehension/ so a
#      legitimate retry within TTL does not spam the operator.
#
# Backward compatibility
# ----------------------
# Any condition that breaks the v2 path falls back to v1's 40-word
# check rather than hard-blocking:
#   - jq / gh unavailable → v1.
#   - Active judge backend unreachable → v1. The judge backend is
#     resolved at runtime (see Stage 0 below):
#       * diff-judge-opus.sh (preferred, ARCA-DEBT-009 hybrid) needs
#         the `claude` CLI on PATH.
#       * diff-judge.sh (legacy fallback, also used by mocked tests
#         that set OLLAMA_URL) needs `curl` to reach Ollama.
#   - Non-interactive shell (CI, scripts, no /dev/tty) → v1.
#   - Diff fetch fails (network, auth) → v1.
# A v1 fallback is logged so we can later tune which paths ought to
# upgrade. Hard-block paths are limited to: timeout, INCOHERENT,
# TOO_SHALLOW.
#
# Bypass
# ------
# Two env vars short-circuit the gate, both audit-logged:
#   ARCA_DIFF_BYPASS=1   — v2-aware bypass (preferred)
#   BYPASS_GATE=1        — v1 legacy bypass, still honored for muscle
#                          memory.
#
# Exit codes
# ----------
#   0 — pass (silent, or with v1-fallback warning on stderr).
#   2 — block (stderr explains why).

set -euo pipefail

# ---------------------------------------------------------------------
# Constants and paths
# ---------------------------------------------------------------------
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-${PWD}}"
STATE_ROOT="${HOME}/.claude/state/diff-comprehension"
BYPASS_LOG="${HOME}/.claude/state/comprehension-gate-bypasses.log"
AUDIT_LOG="${HOME}/.claude/state/diff-comprehension-audit.log"
# Prefer Opus-backed judge if present (ARCA-DEBT-009 hybrid migration);
# fall back to Ollama Qwen judge for backward compatibility and tests
# that mock OLLAMA_URL.
if [[ -f "${PROJECT_DIR}/hooks/lib/diff-judge-opus.sh" ]]; then
    JUDGE_SCRIPT="${PROJECT_DIR}/hooks/lib/diff-judge-opus.sh"
else
    JUDGE_SCRIPT="${PROJECT_DIR}/hooks/lib/diff-judge.sh"
fi
STATS_SCRIPT="${PROJECT_DIR}/hooks/lib/diff-comprehension-stats.sh"

MIN_WORDS=40                 # v1 fallback threshold (legacy parity)
SUMMARY_MIN_WORDS=15         # v2 floor before judge gets called
DEFAULT_TIMEOUT=90
TIMEOUT_SECONDS="${ARCA_DIFF_COMPREHENSION_TIMEOUT:-$DEFAULT_TIMEOUT}"
STATE_TTL_SECONDS=$((24 * 3600))
DIFF_DISPLAY_LINES=40
DIFF_FOR_JUDGE_BYTES=6000

# ---------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------
bump_stats() {
    local bucket="$1"
    [[ -x "$STATS_SCRIPT" ]] || return 0
    bash "$STATS_SCRIPT" "$bucket" 2>/dev/null || true
}

audit() {
    local line="$1"
    mkdir -p "$(dirname "$AUDIT_LOG")"
    printf '%s | %s\n' "$(date -Iseconds)" "$line" >> "$AUDIT_LOG"
}

# Counts whitespace-separated tokens of length >=2. Trivial fillers
# ('a', 'i', '-', '*') are excluded by the length floor. Bullets retained
# as words. Identical to v1 idiom for parity.
count_real_words() {
    local text="$1"
    [[ -z "$text" ]] && { echo 0; return; }
    echo "$text" | tr -s '[:space:]' '\n' | awk 'length >= 2' | wc -l
}

# Best-effort cleanup of state files older than STATE_TTL_SECONDS. Runs
# opportunistically on every invocation so we do not need a cron entry.
purge_stale_state() {
    [[ -d "$STATE_ROOT" ]] || return 0
    find "$STATE_ROOT" -type f -name '*.json' -mmin +1440 -delete 2>/dev/null || true
}

# Hash a string deterministically (sha256, 16 hex chars). Used to detect
# whether a fresh summary matches a previously-approved one for the
# same PR/sha — same hash + same target + APPROVED + within TTL = reuse.
short_hash() {
    local input="$1"
    if command -v sha256sum >/dev/null 2>&1; then
        printf '%s' "$input" | sha256sum | cut -c1-16
    else
        printf '%s' "$input" | md5sum 2>/dev/null | cut -c1-16
    fi
}

# Emit the v1 word-count gate output. Used by every fallback path so we
# preserve PR #18 semantics when the v2 path cannot run end-to-end.
fallback_v1_check() {
    local explanation="$1"
    local source_label="$2"
    local fallback_reason="$3"

    local word_count
    word_count=$(count_real_words "$explanation")

    if (( word_count < MIN_WORDS )); then
        {
            echo "BLOCKED by ARCA PR-merge Comprehension Gate (v1 fallback)."
            echo
            echo "Source checked: ${source_label}"
            echo "Word count: ${word_count} (minimum required: ${MIN_WORDS})."
            echo "Fallback reason: ${fallback_reason}"
            echo
            echo "Required: a substantive explanation of WHAT changed and WHY."
            echo "Fix:"
            echo "  - Edit the PR body or amend the commit body to >=${MIN_WORDS} words."
            echo "  - Or run in an interactive shell with Ollama up to use the v2"
            echo "    judge-based comprehension flow."
            echo "  - Emergency bypass (logged): export ARCA_DIFF_BYPASS=1"
        } >&2
        audit "block_v1 | reason=${fallback_reason} | source=${source_label} | wc=${word_count}"
        return 2
    fi
    audit "pass_v1 | reason=${fallback_reason} | source=${source_label} | wc=${word_count}"
    return 0
}

# ---------------------------------------------------------------------
# Stage 0: payload parsing and command filtering (mirrors v1)
# ---------------------------------------------------------------------
command -v jq >/dev/null 2>&1 || exit 0

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || echo "")
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || echo "")
[[ -z "$COMMAND" ]] && exit 0
[[ -z "$SESSION_ID" ]] && SESSION_ID="unknown-session"

# Skip read-only / print-only commands ONLY if the line is a single
# command (no chain). A chained `echo done; gh pr merge 17` still
# reaches the regex below.
if echo "$COMMAND" | grep -qE '^[[:space:]]*(echo|printf|cat|less|head|tail|grep|awk|sed)([[:space:]]|$)' \
    && ! echo "$COMMAND" | grep -qE '[;|&]'; then
    exit 0
fi

is_gh_merge=false
is_git_push_main=false
pr_num=""

if echo "$COMMAND" | grep -qE '(^|[[:space:];|&]+)gh[[:space:]]+pr[[:space:]]+merge[[:space:]]+[0-9]+'; then
    is_gh_merge=true
    pr_num=$(echo "$COMMAND" | grep -oE 'gh\s+pr\s+merge\s+[0-9]+' | grep -oE '[0-9]+' | head -1)
fi

if echo "$COMMAND" | grep -qE '(^|[[:space:];|&]+)git[[:space:]]+push([[:space:]]+-[^[:space:]]+)*[[:space:]]+[^[:space:]]+[[:space:]]+(main|master)([[:space:]]|$)'; then
    is_git_push_main=true
fi

if [[ "$is_gh_merge" == "false" && "$is_git_push_main" == "false" ]]; then
    exit 0
fi

# ---------------------------------------------------------------------
# Resolve repo working dir from the bash command being evaluated.
#
# Claude Code launches this hook with $PWD = session CWD, which is not
# necessarily the repo where the gated `git push` will run. When the
# evaluated command starts with `cd <path>` (with optional quotes and
# the typical `&& ...` chain), parse that path and switch to it so the
# subsequent `git log / diff / rev-parse` calls evaluate the correct
# repository. Without this, cross-repo workflows (session in repo A,
# push to repo B) would always read repo A's HEAD body and word count,
# producing false negatives that block legitimate pushes.
# ---------------------------------------------------------------------
# Awk-based extractor: scan whitespace-separated tokens; first token after
# the leading `cd` is the candidate path. More portable than bash regex
# alternation, which is finicky with character classes and quotes.
extracted_cwd=$(printf '%s\n' "$COMMAND" | awk '
    {
        for (i = 1; i <= NF; i++) {
            if ($i == "cd" && i == 1 && (i + 1) <= NF) {
                print $(i + 1)
                exit
            }
        }
    }
')
if [[ -n "$extracted_cwd" ]]; then
    # Strip a surrounding pair of single or double quotes if present.
    extracted_cwd="${extracted_cwd#\"}"; extracted_cwd="${extracted_cwd%\"}"
    extracted_cwd="${extracted_cwd#\'}"; extracted_cwd="${extracted_cwd%\'}"
    # Expand a leading ~ to $HOME (explicit slice avoids bash tilde-in-pattern
    # quirks where ${var/#~/...} treats ~ as already-expanded $HOME).
    if [[ "${extracted_cwd:0:1}" == "~" ]]; then
        extracted_cwd="$HOME${extracted_cwd:1}"
    fi
    if [[ -d "$extracted_cwd" ]]; then
        cd "$extracted_cwd"
    fi
fi

# ---------------------------------------------------------------------
# Stage 1: bypass
# ---------------------------------------------------------------------
if [[ "${ARCA_DIFF_BYPASS:-}" == "1" || "${BYPASS_GATE:-}" == "1" ]]; then
    bypass_var="ARCA_DIFF_BYPASS"
    [[ "${BYPASS_GATE:-}" == "1" ]] && bypass_var="BYPASS_GATE"
    echo "[gate] ${bypass_var}=1 — comprehension check skipped (logged)." >&2
    mkdir -p "$(dirname "$BYPASS_LOG")"
    # P0-H1 fix (audit 2026-05-16): COMMAND may contain pasted secrets
    # (inline tokens in remote URLs, Bearer headers passed via env, etc).
    # Mask before persisting to the bypass audit log.
    # shellcheck source=lib/secrets-mask.sh
    LOGGED_COMMAND="$COMMAND"
    if [[ -f "${HOME}/.claude/hooks/lib/secrets-mask.sh" ]]; then
        source "${HOME}/.claude/hooks/lib/secrets-mask.sh"
        if command -v mask_secrets >/dev/null 2>&1; then
            LOGGED_COMMAND=$(mask_secrets "$COMMAND")
        fi
    fi
    printf '%s | %s | %s\n' "$(date -Iseconds)" "$bypass_var" "$LOGGED_COMMAND" >> "$BYPASS_LOG"
    bump_stats bypass
    exit 0
fi

mkdir -p "$STATE_ROOT"
purge_stale_state

# ---------------------------------------------------------------------
# Stage 2: collect diff + legacy explanation text
#
# The legacy explanation (PR body / commit bodies) feeds the v1
# fallback path. The diff feeds the v2 judge path. We always try to
# collect both so any subsequent failure can degrade gracefully.
# ---------------------------------------------------------------------
explanation_text=""
source_label=""
diff_text=""
target_id=""

if $is_gh_merge; then
    if [[ -z "$pr_num" ]]; then
        # Cannot parse — same posture as v1: let it through, gh itself
        # will fail on bad syntax.
        exit 0
    fi
    target_id="pr-${pr_num}"
    if command -v gh >/dev/null 2>&1; then
        explanation_text=$(gh pr view "$pr_num" --json body --jq '.body // ""' 2>/dev/null || echo "")
        diff_text=$(gh pr diff "$pr_num" 2>/dev/null || echo "")
        source_label="PR #${pr_num} body"
    else
        source_label="PR #${pr_num} (gh not installed)"
    fi
fi

if $is_git_push_main; then
    if pending=$(git log --pretty=format:%B '@{u}..HEAD' 2>/dev/null); then
        if [[ -z "$pending" ]]; then
            # Nothing to push, nothing to gate.
            exit 0
        fi
        explanation_text="$pending"
        source_label="commits ahead of upstream"
    elif commit_body=$(git log -1 --pretty=format:%B HEAD 2>/dev/null); then
        explanation_text="$commit_body"
        source_label="HEAD commit body (no upstream tracking)"
    fi
    head_sha=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
    target_id="push-${head_sha:0:12}"
    diff_text=$(git diff '@{u}..HEAD' 2>/dev/null || git diff HEAD~1..HEAD 2>/dev/null || echo "")
fi

# ---------------------------------------------------------------------
# Stage 3: v2 preflight — if anything required is missing, fall back
# to v1 word count over the legacy explanation.
# ---------------------------------------------------------------------
v2_blockers=()

if [[ -z "$diff_text" ]]; then
    v2_blockers+=("diff_empty")
fi
if ! [[ -e /dev/tty ]] || ! [[ -r /dev/tty ]]; then
    v2_blockers+=("no_tty")
fi
# Claude Code runtime: /dev/tty exists and is readable (pointing at
# the user's terminal), but the Bash subprocess is NOT bound to the
# user's interactive prompt loop — they are reading the conversation,
# not waiting for a hook prompt. Reading from /dev/tty here just
# blocks for the full timeout window. Detect via env vars set by the
# CLI itself and fall back to v1 word-count over commit bodies.
if [[ "${CLAUDECODE:-}" == "1" || -n "${CLAUDE_CODE_ENTRYPOINT:-}" ]]; then
    v2_blockers+=("claude_code_runtime")
fi
if [[ ! -f "$JUDGE_SCRIPT" ]]; then
    v2_blockers+=("no_judge_script")
fi
# Backend reachability is judge-specific: the Opus judge spawns
# `claude -p`, the Ollama judge curls localhost. Demand only what the
# active backend actually needs.
case "$(basename "$JUDGE_SCRIPT")" in
    diff-judge-opus.sh)
        if ! command -v claude >/dev/null 2>&1; then
            v2_blockers+=("no_claude_cli")
        fi
        ;;
    diff-judge.sh)
        if ! command -v curl >/dev/null 2>&1; then
            v2_blockers+=("no_curl")
        fi
        ;;
    *)
        # New judge backend was wired in but its preflight wasn't.
        # Fail safe to v1 instead of crashing inside an un-vetted judge.
        v2_blockers+=("unknown_backend")
        ;;
esac

if (( ${#v2_blockers[@]} > 0 )); then
    reason=$(IFS=,; echo "${v2_blockers[*]}")
    bump_stats v1_fallback_no_tty
    if fallback_v1_check "$explanation_text" "$source_label" "$reason"; then
        exit 0
    else
        exit 2
    fi
fi

# ---------------------------------------------------------------------
# Stage 4: reuse cache — same target + APPROVED within TTL = no prompt
# ---------------------------------------------------------------------
state_file="${STATE_ROOT}/${SESSION_ID}__${target_id}.json"
now=$(date +%s)

if [[ -f "$state_file" ]]; then
    cached_verdict=$(jq -r '.verdict // ""' "$state_file" 2>/dev/null)
    cached_at=$(jq -r '.approved_at // 0' "$state_file" 2>/dev/null)
    age=$((now - cached_at))
    if [[ "$cached_verdict" == "APPROVED" ]] && (( age < STATE_TTL_SECONDS )); then
        echo "[gate] reusing APPROVED comprehension verdict for ${target_id} (age=${age}s)." >&2
        bump_stats reused_recent
        audit "reuse | target=${target_id} | age=${age}s"
        exit 0
    fi
fi

# ---------------------------------------------------------------------
# Stage 5: prompt the human, time-boxed
# ---------------------------------------------------------------------
diff_snippet=$(printf '%s' "$diff_text" | head -n "$DIFF_DISPLAY_LINES")
diff_total_lines=$(printf '%s\n' "$diff_text" | wc -l)
diff_for_judge=$(printf '%s' "$diff_text" | head -c "$DIFF_FOR_JUDGE_BYTES")

{
    echo "==============================================================="
    echo " ARCA Diff Comprehension Gate v2 — target: ${target_id}"
    echo "==============================================================="
    echo
    echo "Diff (first ${DIFF_DISPLAY_LINES} of ${diff_total_lines} lines):"
    echo "---------------------------------------------------------------"
    echo "$diff_snippet"
    echo "---------------------------------------------------------------"
    echo
    echo "You have ${TIMEOUT_SECONDS}s to type a summary describing what"
    echo "this change does and why. The judge will compare your summary"
    echo "against the actual diff. Empty / generic summaries fail."
    echo
    echo "Press Ctrl-D when done, or wait for timeout."
    echo
} > /dev/tty

# Read multi-line input until EOF or timeout. `read -t` only times out
# the first line; we wrap the whole capture in a top-level timeout via
# the `timeout` coreutil if present, else degrade to single-line read.
summary_text=""
if command -v timeout >/dev/null 2>&1; then
    summary_text=$(timeout "$TIMEOUT_SECONDS" cat </dev/tty 2>/dev/null || echo "")
else
    # Fallback: single-line read with -t. Less ergonomic but works on
    # systems without GNU coreutils `timeout`.
    if read -t "$TIMEOUT_SECONDS" -r -p "summary> " summary_text </dev/tty 2>/dev/null; then
        :
    else
        summary_text=""
    fi
fi

# A timeout (or empty input) is hard-block. The whole point of v2 is
# to refuse merges when the operator did not engage with the diff.
if [[ -z "${summary_text// /}" ]]; then
    {
        echo "BLOCKED by ARCA Diff Comprehension Gate v2."
        echo "Reason: no summary provided within ${TIMEOUT_SECONDS}s."
        echo "Fix: type a summary describing what the diff does, or set"
        echo "     ARCA_DIFF_BYPASS=1 (audit-logged) for emergencies."
    } >&2
    bump_stats blocked_timeout
    audit "block_timeout | target=${target_id} | timeout=${TIMEOUT_SECONDS}"
    exit 2
fi

# Sanitize the summary the same way diff-judge.sh sanitizes inputs —
# defense in depth in case the judge script is bypassed in tests.
sanitized_summary=$(printf '%s' "$summary_text" \
    | grep -ivE '^[[:space:]]*(VERDICT|REASONING|END_DIFF|END_SUMMARY)[[:space:]]*[_:]')

# Floor before invoking the judge: a 3-word summary cannot possibly
# describe a real diff. Skip the LLM round-trip in that case.
sw=$(count_real_words "$sanitized_summary")
if (( sw < SUMMARY_MIN_WORDS )); then
    {
        echo "BLOCKED by ARCA Diff Comprehension Gate v2."
        echo "Reason: summary too short (${sw} words, minimum ${SUMMARY_MIN_WORDS})."
        echo "Fix: write a substantive summary or bypass with ARCA_DIFF_BYPASS=1."
    } >&2
    bump_stats blocked_shallow
    audit "block_shallow_pre_judge | target=${target_id} | wc=${sw}"
    exit 2
fi

# ---------------------------------------------------------------------
# Stage 6: judge
# ---------------------------------------------------------------------
verdict=$(bash "$JUDGE_SCRIPT" "$sanitized_summary" "$diff_for_judge" 2>/dev/null || echo "TIMEOUT")

audit "judge | target=${target_id} | verdict=${verdict} | summary_wc=${sw} | summary_head=$(printf '%s' "$sanitized_summary" | head -c 80 | tr -d '\n')"

case "$verdict" in
    APPROVED)
        # Persist verdict so a legitimate retry within TTL skips the
        # prompt. Hash the summary so an attacker cannot poison the
        # cache by editing the state file with a different summary
        # under the same APPROVED label.
        sum_hash=$(short_hash "$sanitized_summary")
        cat > "$state_file" <<EOF
{
  "session_id": "${SESSION_ID}",
  "target_id": "${target_id}",
  "verdict": "APPROVED",
  "approved_at": ${now},
  "summary_hash": "${sum_hash}",
  "summary_wc": ${sw}
}
EOF
        bump_stats approved
        echo "[gate] APPROVED — comprehension verified, merge allowed." >&2
        exit 0
        ;;
    INCOHERENT)
        {
            echo "BLOCKED by ARCA Diff Comprehension Gate v2."
            echo "Reason: judge says SUMMARY is INCOHERENT with DIFF."
            echo "Your summary describes a different change than what the"
            echo "diff actually does. Re-read the diff and retry."
            echo
            echo "Bypass (logged): export ARCA_DIFF_BYPASS=1"
        } >&2
        bump_stats blocked_incoherent
        exit 2
        ;;
    TOO_SHALLOW)
        {
            echo "BLOCKED by ARCA Diff Comprehension Gate v2."
            echo "Reason: judge says SUMMARY is TOO_SHALLOW."
            echo "Your summary is generic boilerplate with no concrete"
            echo "detail traceable to the diff. Name specific files,"
            echo "functions or behaviors and retry."
            echo
            echo "Bypass (logged): export ARCA_DIFF_BYPASS=1"
        } >&2
        bump_stats blocked_shallow
        exit 2
        ;;
    TIMEOUT|*)
        # Judge unreachable. Fail-safe: degrade to v1 word count over
        # the typed summary (not the legacy PR body), since the human
        # already engaged interactively.
        bump_stats v1_fallback_judge
        if (( sw >= MIN_WORDS )); then
            echo "[gate] WARN: judge unavailable, summary passes v1 floor (${sw} words)." >&2
            audit "fallback_judge_pass | target=${target_id} | wc=${sw}"
            exit 0
        fi
        {
            echo "BLOCKED by ARCA Diff Comprehension Gate v2."
            echo "Reason: judge unavailable AND summary below v1 floor"
            echo "(${sw} words, need ${MIN_WORDS}). Either start Ollama or"
            echo "write a longer summary. Bypass: ARCA_DIFF_BYPASS=1."
        } >&2
        audit "fallback_judge_block | target=${target_id} | wc=${sw}"
        exit 2
        ;;
esac
