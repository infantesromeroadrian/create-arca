#!/usr/bin/env bash
# skills/dashboard-build/run.sh — ADR-049 dashboard + continuous architecture review.
#
# Single source of truth for /dashboard-build. SKILL.md and the future slash
# command are thin pointers — same separation as skills/adr-new/. Parses
# backlog.md + C1 sidecars + existing architect reviews into the intermediate
# JSON shape defined by docs/specs/dashboard-build/schema.json, optionally
# invokes @architect-ai for the missing cycle review, then renders
# templates/dashboard/index.html into <project>/dashboard/index.html.
#
# Exit codes mirror docs/specs/dashboard-build/parser-contract.md:
#   0   success — JSON on stdout, dashboard written
#   10  E101 backlog.md not found
#   11  E102 backlog.md empty or invalid UTF-8
#   12  E103 YAML frontmatter without opt-in
#   13  E104 no '### MUST' header
#   20-29 E2xx canonical-table structural (delegated to parser core, T8)
#   30+   E3xx WONT reduced-schema structural (delegated)
#   90  E901 internal self-check or template substitution failure
#   100 argv/usage error (skill-level)
#   101 path traversal / out-of-repo --project-root
#   102 missing sibling artefact (template / schema / parser-contract)

set -euo pipefail
IFS=$'\n\t'

# Resolve the directory containing this script BEFORE any reference downstream
# (`set -u` would crash on an unbound `$SKILL_DIR`). BASH_SOURCE[0] points to
# this run.sh regardless of how it was invoked (absolute path, relative, sourced).
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SKILL_DIR

readonly SCHEMA_VERSION="1.0.0"
readonly MIN_CYCLE=1
readonly MAX_CYCLE=14
readonly PROJECT_DIR_DEFAULT="${CLAUDE_PROJECT_DIR:-${PWD}}"

# Logging: stderr only. stdout is reserved for the intermediate JSON contract.
log()       { printf '[dashboard-build] [%s] %s %s\n' "$1" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$2" >&2; }
log_info()  { log INFO  "$*"; }
log_warn()  { log WARN  "$*"; }
log_error() { log ERROR "$*"; }

usage() {
    cat <<'USAGE' >&2
Usage: dashboard-build --project-root <abs-path> --cycle <N> [options]

Required:
  --project-root <path>       Absolute path to project root. Must resolve
                              within the current repo workspace; '..' and
                              out-of-repo symlinks are rejected.
  --cycle <N>                 Cycle number 1..14 (ARCA Pipeline v4.0).

Options:
  --accept-yaml-frontmatter   Opt in to mixed Markdown-table + YAML format.
  --self-check                Run `jq empty` on the emitted JSON.
  --test-exit <code>          Exit immediately with <code> (test harness).

Env: DASHBOARD_BUILD_ACCEPT_YAML=1 is equivalent to --accept-yaml-frontmatter.
Exit codes follow docs/specs/dashboard-build/parser-contract.md.
USAGE
}

# --- Argument parsing -------------------------------------------------------

PROJECT_ROOT=""; CYCLE=""; SELF_CHECK=0; TEST_EXIT=""
ACCEPT_YAML=$([[ "${DASHBOARD_BUILD_ACCEPT_YAML:-0}" == "1" ]] && echo 1 || echo 0)

while [[ $# -gt 0 ]]; do
    case "$1" in
        --project-root) [[ $# -ge 2 ]] || { log_error "--project-root needs an argument"; usage; exit 100; }
                        PROJECT_ROOT="$2"; shift 2 ;;
        --cycle)        [[ $# -ge 2 ]] || { log_error "--cycle needs an argument"; usage; exit 100; }
                        CYCLE="$2"; shift 2 ;;
        --accept-yaml-frontmatter) ACCEPT_YAML=1; shift ;;
        --self-check)              SELF_CHECK=1; shift ;;
        --test-exit)    [[ $# -ge 2 ]] || { log_error "--test-exit needs an argument"; usage; exit 100; }
                        TEST_EXIT="$2"; shift 2 ;;
        --help|-h)      usage; exit 0 ;;
        *)              log_error "unknown argument: $1"; usage; exit 100 ;;
    esac
done

# Test harness: T9 asserts each exit code without staging a broken backlog.
if [[ -n "$TEST_EXIT" ]]; then
    [[ "$TEST_EXIT" =~ ^[0-9]+$ ]] || { log_error "--test-exit needs an integer, got '$TEST_EXIT'"; exit 100; }
    exit "$TEST_EXIT"
fi

[[ -n "$PROJECT_ROOT" ]] || { log_error "--project-root is required"; usage; exit 100; }
[[ -n "$CYCLE" ]]        || { log_error "--cycle is required"; usage; exit 100; }
if ! [[ "$CYCLE" =~ ^[0-9]+$ ]] || (( CYCLE < MIN_CYCLE || CYCLE > MAX_CYCLE )); then
    log_error "--cycle must be integer in [${MIN_CYCLE}, ${MAX_CYCLE}], got '$CYCLE'"; exit 100
fi

# --- Path sanitisation (flagged ciclo 1 by @code-critic) --------------------
# Reject '..' literal segments, canonicalise with realpath, require the
# resolved path to live under the repo workspace. A symlink escaping the repo
# is caught here even when the literal path looked safe.

if [[ "$PROJECT_ROOT" == *".."* ]]; then
    log_error "path traversal rejected: '..' segment in --project-root"; exit 101
fi
[[ -d "$PROJECT_ROOT" ]] || { log_error "--project-root is not a directory: $PROJECT_ROOT"; exit 101; }

PROJECT_ROOT_ABS=$(realpath "$PROJECT_ROOT" 2>/dev/null || true)
WORKSPACE_ROOT_ABS=$(realpath "$PROJECT_DIR_DEFAULT" 2>/dev/null || true)
[[ -n "$PROJECT_ROOT_ABS" && -d "$PROJECT_ROOT_ABS" ]] \
    || { log_error "cannot canonicalise --project-root: $PROJECT_ROOT"; exit 101; }
[[ -n "$WORKSPACE_ROOT_ABS" ]] || { log_error "cannot canonicalise workspace root: $PROJECT_DIR_DEFAULT"; exit 101; }

# Path-traversal defence: client project must resolve INSIDE the workspace
# prefix (CLAUDE_PROJECT_DIR or PWD). This blocks symlink escapes and `..`
# attempts. The workspace prefix is the OPERATOR-controlled boundary; the
# skill code repo location is separate (resolved below from SKILL_DIR).
case "$PROJECT_ROOT_ABS" in
    "$WORKSPACE_ROOT_ABS"|"$WORKSPACE_ROOT_ABS"/*) : ;;
    *) log_error "project-root resolves outside workspace prefix"
       log_error "  resolved:  $PROJECT_ROOT_ABS"
       log_error "  workspace: $WORKSPACE_ROOT_ABS"
       log_error "  hint: export CLAUDE_PROJECT_DIR to the parent of both the ARCA repo and the client project"
       exit 101 ;;
esac

# Skill code repo root: where the template / schema / parser-contract live.
# Derived from SKILL_DIR (the location of THIS run.sh), independent of the
# operator's CLAUDE_PROJECT_DIR. This keeps the skill operable when the
# client project lives outside .claude/.
SKILL_REPO_ROOT="$(cd "$SKILL_DIR/../.." && pwd)"
readonly SKILL_REPO_ROOT

# --- Input paths ------------------------------------------------------------

BACKLOG_PATH="${PROJECT_ROOT_ABS}/docs/c1-discovery/backlog.md"
SIDECAR_DIR="${PROJECT_ROOT_ABS}/docs/c1-discovery"
REVIEWS_DIR="${PROJECT_ROOT_ABS}/docs/architecture/reviews"
DASHBOARD_OUT_DIR="${PROJECT_ROOT_ABS}/dashboard"
DASHBOARD_OUT="${DASHBOARD_OUT_DIR}/index.html"
TEMPLATE="${SKILL_REPO_ROOT}/templates/dashboard/index.html"
PARSER_CONTRACT="${SKILL_REPO_ROOT}/docs/specs/dashboard-build/parser-contract.md"
SCHEMA="${SKILL_REPO_ROOT}/docs/specs/dashboard-build/schema.json"

# ADR-051: source format auto-detection. If backlog.md does not exist but
# todos.csv does, skip the E1xx input checks (parser-core.py handles them via
# csv_adapter). Only validate backlog.md when it IS the intended source.
CSV_PATH="${PROJECT_ROOT_ABS}/todos.csv"
if [[ ! -f "$BACKLOG_PATH" ]] && [[ -f "$CSV_PATH" ]]; then
    log_info "source format: csv (todos.csv) — skipping backlog.md E1xx checks"
    SOURCE_FORMAT="csv"
else
    SOURCE_FORMAT="backlog"
fi

# E1xx: input I/O / encoding — only for backlog.md source.
if [[ "$SOURCE_FORMAT" == "backlog" ]]; then
    [[ -f "$BACKLOG_PATH" ]] || { log_error "E101 backlog.md not found at $BACKLOG_PATH"; exit 10; }
    [[ -s "$BACKLOG_PATH" ]] || { log_error "E102 backlog.md empty at $BACKLOG_PATH"; exit 11; }
    iconv -f UTF-8 -t UTF-8 "$BACKLOG_PATH" >/dev/null 2>&1 \
        || { log_error "E102 backlog.md is not valid UTF-8: $BACKLOG_PATH"; exit 11; }
fi

# YAML frontmatter: E103 unless opted in — backlog.md source only.
if [[ "$SOURCE_FORMAT" == "backlog" ]] && head -n1 "$BACKLOG_PATH" | grep -qE '^---[[:space:]]*$'; then
    if (( ACCEPT_YAML == 0 )); then
        log_error "E103 backlog.md begins with YAML frontmatter; --accept-yaml-frontmatter not set"
        log_error "  set the flag or DASHBOARD_BUILD_ACCEPT_YAML=1 to opt in"
        exit 12
    fi
    log_warn "YAML frontmatter detected and accepted via opt-in"
fi

# MUST header presence — E104 (ADR-040 §1.5 lenient on case) — backlog only.
if [[ "$SOURCE_FORMAT" == "backlog" ]]; then
    grep -qiE '^###[[:space:]]+MUST[[:space:]]*$' "$BACKLOG_PATH" \
        || { log_error "E104 no '### MUST' header in $BACKLOG_PATH (ADR-040 §1.5)"; exit 13; }
fi

# Repo-level invariants (102) — not project-specific.
[[ -f "$PARSER_CONTRACT" ]] || { log_error "missing parser contract: $PARSER_CONTRACT (T4)"; exit 102; }
[[ -f "$SCHEMA" ]]          || { log_error "missing schema: $SCHEMA (T4)"; exit 102; }

# --- Delegate to parser-core.py (T11 — full canonical-table + HTML hydrator)

INTERMEDIATE_JSON=$(mktemp)
trap 'rm -f "$INTERMEDIATE_JSON" 2>/dev/null || true' EXIT

PARSER_CORE="$SKILL_DIR/parser-core.py"
[[ -f "$PARSER_CORE" ]] || { log_error "missing parser-core.py at $PARSER_CORE (T11)"; exit 102; }
command -v python3 >/dev/null 2>&1 || { log_error "python3 not found in PATH (required by parser-core.py >= 3.10)"; exit 102; }

YAML_FLAG=()
(( ACCEPT_YAML == 1 )) && YAML_FLAG=(--accept-yaml-frontmatter)

# JSON mode: parser-core.py owns sidecar reading, table parsing, dep expansion,
# RICE preservation, cycle normalisation, status overlay merge, reviews glob,
# warnings emission, and self-check. Exit codes propagate per parser-contract.md
# E1xx/E2xx/E3xx/E4xx/E9xx catalogue.
# Exit-code propagation pattern: run the command under `|| capture` so the
# parent shell sees the REAL exit code. `if ! cmd; then $?` is bash 101 wrong
# — `$?` after the `!` test reads as 0 inside the then-branch (B-3 ciclo 2/2).
# The contract codes (E1xx/E2xx/E3xx/E4xx/E9xx) from parser-core.py must
# survive verbatim to run.sh's exit so cycle-dashboard-enforcer.sh (T7) and
# CI can key off them.
parser_exit=0
python3 "$PARSER_CORE" \
        --mode json \
        --project-root "$PROJECT_ROOT_ABS" \
        --cycle "$CYCLE" \
        --self-check \
        ${YAML_FLAG[@]:+"${YAML_FLAG[@]}"} > "$INTERMEDIATE_JSON" || parser_exit=$?
if (( parser_exit != 0 )); then
    log_error "parser-core.py json mode failed with exit code $parser_exit"
    exit "$parser_exit"
fi
(( SELF_CHECK == 1 )) && log_info "self-check passed (parser-core --self-check)"

# --- Ad-hoc architect invocation (ADR-049 Option B) -------------------------
# agents/architect-ai.md is NOT modified. The skill is the orchestration site
# for the continuous review per cycle. From bash we can only detect the
# missing artefact and instruct the operator (or the hook in T7) to satisfy
# it; direct Agent SDK invocation is not safe to assume from a non-interactive
# shell.

REVIEW_FILE="${REVIEWS_DIR}/architect-review-C${CYCLE}.md"
if [[ ! -f "$REVIEW_FILE" ]]; then
    log_warn "architect-review-C${CYCLE}.md missing at $REVIEW_FILE"
    log_warn "  invoke @architect-ai with the cycle-${CYCLE} review prompt and write to that path"
    log_warn "  (ADR-049 Option B: agents/architect-ai.md is NOT modified)"
fi

# --- Render dashboard HTML via parser-core.py --mode html -------------------
# parser-core.py hydrates BOTH global scalars AND iterable placeholders
# (CARDS_BACKLOG/INPROGRESS/DONE/BLOCKED loops, OBJECTIVES, STAKEHOLDERS,
# SUCCESS_METRICS, REVIEWS, WARNINGS, IFEMPTY branches, IFANY conditionals).
# HTML-escape happens at substitution boundary per template T5 banner contract.

if [[ ! -f "$TEMPLATE" ]]; then
    log_warn "template not yet available: $TEMPLATE (T5 deliverable)"
    log_warn "  emitting intermediate JSON only; HTML render skipped"
    cat "$INTERMEDIATE_JSON"; exit 0
fi

# Output-directory creation MUST translate filesystem errors (EACCES, ENOSPC,
# ENOTDIR on a parent path) into the E402 contract code. Per parser-contract.md
# E4xx catalogue, exit 41 is reserved for "output path unwritable". Without
# this trap the bash-generic exit (1) leaks through and downstream tooling
# (cycle-dashboard-enforcer.sh, CI) keying off exit 41 never sees the agreed
# signal.
if ! mkdir -p "$DASHBOARD_OUT_DIR" 2>/dev/null; then
    log_error "E402 output path unwritable: cannot create directory $DASHBOARD_OUT_DIR"
    exit 41
fi

# Same exit-code propagation pattern as the JSON mode above. `|| capture` so
# the real exit code from parser-core.py reaches run.sh's exit, not the bash
# if-test default of 0 (see B-3 fix above).
parser_exit=0
python3 "$PARSER_CORE" \
        --mode html \
        --project-root "$PROJECT_ROOT_ABS" \
        --cycle "$CYCLE" \
        --template "$TEMPLATE" \
        ${YAML_FLAG[@]:+"${YAML_FLAG[@]}"} > "$DASHBOARD_OUT.tmp" || parser_exit=$?
if (( parser_exit != 0 )); then
    log_error "parser-core.py html mode failed with exit code $parser_exit"
    rm -f "$DASHBOARD_OUT.tmp"
    exit "$parser_exit"
fi

# mv across filesystems / EACCES / ENOSPC also surfaces as E402. The temp file
# was created in the same dir (DASHBOARD_OUT_DIR) so a same-filesystem rename
# should normally succeed; failure here means filesystem perms changed mid-run.
if ! mv "$DASHBOARD_OUT.tmp" "$DASHBOARD_OUT" 2>/dev/null; then
    log_error "E402 output path unwritable: cannot rename $DASHBOARD_OUT.tmp -> $DASHBOARD_OUT"
    rm -f "$DASHBOARD_OUT.tmp"
    exit 41
fi

log_info "dashboard written: $DASHBOARD_OUT"
log_info "cycle: C${CYCLE}  project: $(basename "$PROJECT_ROOT_ABS")  schema: $SCHEMA_VERSION"

cat "$INTERMEDIATE_JSON"
exit 0
