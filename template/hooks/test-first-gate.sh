#!/bin/bash
set -uo pipefail
umask 077

# test-first-gate.sh — TDD entry guard for the ARCA harness (ADR-106).
#
# A SINGLE hook wired into THREE events; it branches on `hook_event_name`:
#   - PostToolUseFailure  -> RED sensor  (records a failing-pytest observation)
#   - PreToolUse:Write|Edit -> GATE      (refuses feature-code write without RED)
#   - PostToolUse:Bash    -> GREEN sensor (telemetry only, never blocks)
#
# WHY a multi-event hook (ADR-106 D1):
#   "a test failed" is only observable from PostToolUseFailure (a failing pytest
#   exits non-zero and routes there, NOT to PostToolUse:Bash — verified empirically,
#   CLI 2.1.167, corroborated by post-tool-use-failure-telemetry.sh / ADR-094).
#   "feature code is being written" is only observable from the Write/Edit
#   file_path on PreToolUse, BEFORE the mutation lands. No single event sees both,
#   so the per-session log is the shared blackboard — same pattern the
#   code-critic gate uses to correlate PRODUCER / CODE_CRITIC_OK across Agent calls.
#
# INVARIANTS (non-negotiable, ADR-106 Rationale "fail-open everywhere"):
#   - SHADOW-FIRST: ARCA_TDD_GATE_SHADOW defaults to 1. In shadow the gate logs a
#     would-block decision and exits 0 (allow). Blocking (exit 2) only when
#     SHADOW=0 is set explicitly.
#   - FAIL-OPEN on EVERY error path: missing jq / empty stdin / empty session_id /
#     jq parse failure / unwritable state dir / non-feature file -> exit 0. A TDD
#     guard must NEVER brick the harness with an internal-error exit 2.
#   - BYPASS audited, not silent: ARCA_TDD_GATE_DISABLE=1 -> exit 0 + one audit line.
#   - flock -x for append, flock -s for read; session_id sanitized + length-capped.
#
# LOG GRAMMAR (one event per line, space-separated — the gate greps ' RED '):
#   <nanos> RED   <abs_cwd>            # PostToolUseFailure, pytest double-confirmed
#   <nanos> GRN   <abs_cwd>            # PostToolUse:Bash, pytest exit 0 (telemetry)
#   <nanos> WRITE <feature_file_path>  # PreToolUse gate allowed a feature write
#
# Test override: ARCA_TDD_GATE_STATE_DIR redirects state to an isolated tmpdir.

# --- Guard 0: jq is mandatory; without it we cannot parse safely -> fail-open ---
command -v jq >/dev/null 2>&1 || exit 0

# --- Read stdin once. Empty stdin -> every jq below yields empty -> fail-open ---
INPUT=$(cat)

# --- Bypass (ADR-106 D5): audited, then allow. Resolve a state dir best-effort
#     purely to drop the audit line; never fail the bypass on a write error.   ---
if [[ "${ARCA_TDD_GATE_DISABLE:-0}" == "1" ]]; then
  BYPASS_DIR="${ARCA_TDD_GATE_STATE_DIR:-${HOME}/.claude/state/tdd-gate}"
  if mkdir -p "$BYPASS_DIR" 2>/dev/null; then
    BYPASS_TS=$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo "")
    printf '%s bypass ARCA_TDD_GATE_DISABLE=1\n' "$BYPASS_TS" \
      >> "${BYPASS_DIR}/bypasses.log" 2>/dev/null || true
  fi
  exit 0
fi

# --- Parse the event discriminator + tool. Any parse failure -> empty -> exit 0 -
EVENT=$(printf '%s' "$INPUT" | jq -r '.hook_event_name // empty' 2>/dev/null || echo "")
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || echo "")

# --- Session id keys the per-session log. Sanitize to [A-Za-z0-9_-], cap 64
#     (anti path-traversal, copied verbatim from code-critic-gate-enforcer.sh).
#     Empty after sanitization -> no usable key -> fail-open.                  ---
SID_RAW=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || echo "")
SID=$(printf '%s' "$SID_RAW" | tr -cd 'A-Za-z0-9_-' | cut -c1-64)
[[ -z "$SID" ]] && exit 0

# --- State dir. Unwritable -> fail-open (the guard must not become a hard dep). -
STATE_DIR="${ARCA_TDD_GATE_STATE_DIR:-${HOME}/.claude/state/tdd-gate}"
mkdir -p "$STATE_DIR" 2>/dev/null || exit 0

LOG="${STATE_DIR}/${SID}.log"
LOCK="${LOG}.lock"
NANOS=$(date +%s%N)
SHADOW="${ARCA_TDD_GATE_SHADOW:-1}"

# is_feature_code — classify a path per ADR-106 D4. Returns 0 (feature code,
# gate-eligible) only when ALL hold: it is a .py file, NOT a test, NOT docs/config,
# and lives under a recognized feature root (or is a repo-root *.py). Everything
# ambiguous biases toward ALLOW (return 1) — fail-toward-not-blocking.
is_feature_code() {
  local fp="$1"

  # Must be Python. Non-.py -> always allow (v1 is Python-only).
  case "$fp" in
    *.py) ;;
    *) return 1 ;;
  esac

  # Tests are NEVER gated — the first RED test write must always be allowed,
  # or TDD is impossible.
  case "$fp" in
    */test_*.py|test_*.py|*_test.py|*/tests/*|*/test/*|*/conftest.py|conftest.py)
      return 1 ;;
  esac

  # Docs / config / IDE state are never feature code.
  case "$fp" in
    */docs/*|docs/*|*/.claude/*|.claude/*|*.md|*.json|*.toml|*.yaml|*.yml|*.cfg|*.ini)
      return 1 ;;
  esac

  # Feature roots: a .py under one of these is gate-eligible. This list is a
  # CLOSED ALLOWLIST — only src/lib/app/hooks/agents/scripts count as a feature
  # root. Anything NOT matched here falls through to the repo-root-only rule
  # below (a bare *.py at the repo root is feature code; a *.py in any other
  # subdirectory is NOT gated). Widening the gate's reach means editing this
  # list deliberately, never an accidental catch-all. (ADR-106 D4 documents
  # the rationale; the bias is fail-toward-ALLOW.)
  case "$fp" in
    */src/*|src/*|*/lib/*|lib/*|*/app/*|app/*|*/hooks/*|hooks/* \
    |*/agents/*|agents/*|*/scripts/*|scripts/*)
      return 0 ;;
  esac

  # Repo-root *.py (no slash) -> feature code.
  case "$fp" in
    */*) return 1 ;;   # has a directory component, not under any feature root
    *.py) return 0 ;;  # bare name like "main.py" at repo root
  esac

  return 1
}

# is_pytest_cmd — return 0 iff the given command string invokes pytest at the
# START of a command segment (anchored, NOT a loose substring), tolerating the
# real-world prefixes a pytest run carries:
#   - leading whitespace at the segment start;
#   - zero or more inline env assignments (PYTHONPATH=. FOO=bar pytest ...);
#   - an OPTIONAL dependency-runner from a CLOSED ALLOWLIST
#     (uv/poetry/pdm/hatch/pipenv/rye/nox/tox/conda/micromamba/mamba) + run|exec,
#     followed ONLY by a CLOSED grammar of runner flags — never a bareword
#     command. A value is consumed (space-separated) only for the four env-name
#     flags -n/-p/--name/--prefix (`conda run -n env pytest`); short flags
#     (`-xvs`) and `--key=val` flags are flag-only. This closed grammar is what
#     rejects `uv run pip install pytest` (pip is a bareword command, not a flag)
#     and `conda run -n env which pytest` (which is the command being run, not
#     pytest) without dropping any legitimate pytest invocation.
#   - an OPTIONAL `pythonX[.Y] -m ` (python / python3 / python3.12).
# The runner is an allowlist on purpose: an open runner word would mis-read
# `echo run pytest` as runner=echo (a false positive proven in review). The
# segment-start anchor `(^|[;&|])[[:space:]]*` is what keeps `echo pytest`,
# `grep pytest`, and `# pytest` OUT — pytest is only a RED signal when it is the
# command being run, not an argument to another command. The trailing
# `pytest([ ;&|]|$)` anchors the END so `pytest;echo done` matches but
# `pytest.ini` and `mypytest` do not.
# Definitive regex resolved by @architect-ai (ADR-106 code-critic escalation);
# verified here against the full 30-case corpus before adoption.
# Shared by the RED sensor (branch 1) and the GREEN sensor (branch 3) so the two
# can never drift apart.
PYTEST_CMD_RE='(^|[;&|])[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]+ +)*((uv|poetry|pdm|hatch|pipenv|rye|nox|tox|conda|micromamba|mamba) +(run|exec)( +((-n|-p|--name|--prefix) +[A-Za-z0-9_.:/-]+|--[A-Za-z0-9_-]+=[^ ]+|-{1,2}[A-Za-z0-9_-]+))* +)?(python[0-9.]* +-m +)?pytest([ ;&|]|$)'
is_pytest_cmd() {
  printf '%s' "$1" | grep -qE "$PYTEST_CMD_RE"
}

# ===========================================================================
# BRANCH 1 — RED sensor (PostToolUseFailure)
# ===========================================================================
if [[ "$EVENT" == "PostToolUseFailure" ]]; then
  CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || echo "")
  ERR=$(printf '%s' "$INPUT" | jq -r '.tool_response.error // .error // empty' 2>/dev/null || echo "")

  # Double confirmation (ADR-106 D1) — BOTH mandatory, else this is the
  # Bash-fail-no-pytest risk class (a broken git push / failed cd also lands
  # here) and MUST NOT be mistaken for a RED test run.
  #   (1) command is an ANCHORED pytest invocation (not a loose substring),
  #   (2) error is an "Exit code N" failure string.
  if is_pytest_cmd "$CMD" \
     && printf '%s' "$ERR" | grep -qE 'Exit code [0-9]+'; then
    { flock -x 9; printf '%s RED %s\n' "$NANOS" "$PWD" >> "$LOG"; } 9>"$LOCK"
  fi
  exit 0
fi

# ===========================================================================
# BRANCH 2 — GATE (PreToolUse on Write|Edit)
# ===========================================================================
if [[ "$EVENT" == "PreToolUse" ]] && { [[ "$TOOL" == "Write" ]] || [[ "$TOOL" == "Edit" ]]; }; then
  FP=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.filePath // empty' 2>/dev/null || echo "")
  [[ -z "$FP" ]] && exit 0

  # Not feature code (test / doc / config / non-Python / unusual path) -> allow.
  is_feature_code "$FP" || exit 0

  # Shared-state read uses a shared lock so a concurrent RED append cannot
  # interleave. grep -c ' RED ' counts RED lines for THIS session.
  HAS_RED=$({ flock -s 9; grep -c ' RED ' "$LOG" 2>/dev/null || echo 0; } 9>"$LOCK")
  # Coerce to a plain integer (grep -c can emit "0" on a missing file via the
  # || fallback; guard against any stray non-numeric).
  [[ "$HAS_RED" =~ ^[0-9]+$ ]] || HAS_RED=0

  if [[ "$HAS_RED" -gt 0 ]]; then
    # A RED was observed this session -> test-first order honored -> ALLOW,
    # and record the WRITE so C8 (ADR-056) can audit RED-before-WRITE order.
    { flock -x 9; printf '%s WRITE %s\n' "$NANOS" "$FP" >> "$LOG"; } 9>"$LOCK"
    exit 0
  fi

  # VIOLATION: feature code write with zero RED runs this session.
  if [[ "$SHADOW" == "1" ]]; then
    # Shadow: log the would-be decision, warn on stderr, ALLOW (exit 0).
    SHADOW_FILE="${HOME}/.claude/tdd-gate-shadow.jsonl"
    # Ensure the parent dir exists; ~/.claude may be absent in a fresh sandbox.
    # Best-effort — a failed mkdir must not turn an allow into a hard error.
    mkdir -p "$(dirname "$SHADOW_FILE")" 2>/dev/null || true
    SHADOW_TS=$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo "")
    jq -nc \
      --arg ts "$SHADOW_TS" \
      --arg event "would_block" \
      --arg file "$FP" \
      --arg mode "shadow" \
      '{ts:$ts, event:$event, file:$file, mode:$mode}' \
      >> "$SHADOW_FILE" 2>/dev/null || true
    printf '[TDD-GATE shadow] would block write to %s — no RED (failing pytest) observed this session. Allowing (shadow mode).\n' "$FP" >&2
    exit 0
  fi

  # Blocking mode (SHADOW=0): emit the reason and exit 2 to refuse the write.
  printf '[TDD-GATE] Refusing write to %s: no RED this session (run a failing pytest before writing feature code). Bypass with ARCA_TDD_GATE_DISABLE=1.\n' "$FP" >&2
  exit 2
fi

# ===========================================================================
# BRANCH 3 — GREEN sensor (PostToolUse on Bash) — telemetry only, never blocks
# ===========================================================================
if [[ "$EVENT" == "PostToolUse" ]] && [[ "$TOOL" == "Bash" ]]; then
  CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || echo "")
  EXIT_CODE=$(printf '%s' "$INPUT" | jq -r '.tool_response.exitCode // .tool_response.exit_code // empty' 2>/dev/null || echo "")
  if [[ -n "$CMD" ]] && is_pytest_cmd "$CMD" && [[ "$EXIT_CODE" == "0" ]]; then
    { flock -x 9; printf '%s GRN %s\n' "$NANOS" "$PWD" >> "$LOG"; } 9>"$LOCK" 2>/dev/null || true
  fi
  exit 0
fi

# Unknown / unhandled event shape -> fail-open.
exit 0
