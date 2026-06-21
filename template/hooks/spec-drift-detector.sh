#!/usr/bin/env bash
# ARCA — Spec drift detector (ADR-027 S4) — PostToolUse:Bash advisory hook
#
# Detects divergence between ADR-028 SDD bundles (docs/specs/<feature>/) and
# the spec.lock.json fingerprint they were generated with. Fires AFTER any
# Bash invocation that performs `git push` or `gh pr merge` on a repo that
# contains at least one bundle, walks every bundle, and recomputes SHA256
# of files declared in the lock vs the declared hashes.
#
# ADVISORY ONLY:
#   Per ADR-027 §"Refinements to the orchestrator's plan", drift detection
#   runs as advisory for the first 30 days. ML training scripts and POC
#   iterations would create false positives if this blocked. Promotion to
#   bloqueante is conditioned on stats showing < 5% FP rate over the window
#   — ⟦ user_name ⟧ decides post-S6.
#
# POSTTOOLUSE TIMING (known limitation, A1 from @code-critic ciclo 1):
#   This hook fires AFTER `git push` completes. The push has already landed
#   in the remote when the operator sees the warning. Defendable today
#   because (a) advisory mode never blocks anyway, (b) the push carries
#   the bundle files (which are committed in a previous step), (c) S6 plan
#   migrates this to PreToolUse:Bash with conditional blocking. Until S6
#   the warning is post-mortem — fix the lock and force-push or amend.
#
# DRIFT MEANS:
#   spec.md was edited but spec.lock.json hash entry stale → human forgot
#   to re-fingerprint after closing TODOs. Or the inverse — code drifted
#   but spec didn't follow.
#
# SECURITY HARDENING (B1 closed by @code-critic ciclo 1 PoC + ADR-028 spirit):
#   spec.lock.json is UNTRUSTED INPUT — a malicious commit can declare
#   .files entries like "../../../etc/passwd" to make this hook compute
#   SHA256 of arbitrary system files and leak truncated hashes via stderr
#   (CWE-22 + CWE-200). Defense-in-depth applied:
#     L1. jq whitelist filter on file keys: only extension-bound names
#         matching ^[a-zA-Z0-9._-]+\.(md|yaml|yml|json)$ pass through.
#     L2. bash check: reject any key containing /, .., or null bytes
#         even if jq let it through (belt + suspenders).
#     L3. realpath containment: TARGET_REAL must be under BUNDLE_REAL.
#         Closes symlink-escape too (e.g. lock declares "innocent.md"
#         but bundle dir contains a symlink innocent.md → /etc/passwd).
#   A REJECTED entry counts as drift and is reported to stderr WITHOUT
#   the suspicious filename in plain — replaced with <rejected-path>.
#
# OUTPUT (advisory):
#   stderr nudge listing each drifted/rejected bundle. exit 0 always.
#
# STATS:
#   ~/.claude/state/spec-drift-stats.json buckets:
#     scanned         = bundles found and inspected
#     drift_clean     = bundle matched lock exactly
#     drift_found     = at least one file diverged from lock
#     skipped_no_lock = bundle dir without spec.lock.json (or invalid JSON)
#     rejected_path   = filename rejected by L1/L2/L3 hardening
#     bypass          = ARCA_SPEC_DRIFT_BYPASS=1 set
#
# ENV OVERRIDES (test surface):
#   ARCA_SPEC_DRIFT_STATE_DIR  — redirect stats file (pytest tmpdir)
#   ARCA_SPEC_DRIFT_BYPASS=1   — skip detection entirely (audit logged)
#   ARCA_SPEC_DRIFT_REPO_HINT  — force the repo path being scanned
#                                (otherwise derived from cwd or `git -C`)
#
# DEUDA REGISTRADA (no bloquea S4 — ⟦ user_name ⟧ valida en S6 review):
#   - A2: matcher case glob es laxo. Falsos positivos posibles (echo "git push later").
#         Advisory mode + exit 0 → impact cero. Mejorar a token-aware en S6.
#   - A3: lectura del lock + sha256 sin flock entre múltiples /spec-new
#         concurrentes. Riesgo: stats best-effort observan estados intermedios.
#         Aceptable para advisory; estricto si promueve a bloqueante.
#
# Hook contract: receives Claude Code PostToolUse JSON on stdin. Reads
# `tool_input.command` to decide whether to fire.

set -uo pipefail

# ---- Read tool_input from stdin (Claude Code hook contract) ---------------
INPUT="$(cat 2>/dev/null || true)"
if [ -z "$INPUT" ]; then
    exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
    # No jq → cannot parse hook payload. Silent exit; the higher-level
    # ARCA setup expects jq globally (same assumption as auto-adr-detector).
    exit 0
fi

CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$CMD" ] && exit 0

# ---- Matcher: only fire on git push or gh pr merge ------------------------
case "$CMD" in
    *"git push"*|*"git-push"*) ;;
    *"gh pr merge"*) ;;
    *) exit 0 ;;
esac

# ---- Bypass surface (audit-logged) ----------------------------------------
STATE_DIR="${ARCA_SPEC_DRIFT_STATE_DIR:-${HOME}/.claude/state}"
STATS_FILE="${STATE_DIR}/spec-drift-stats.json"
AUDIT_LOG="${STATE_DIR}/spec-drift-audit.log"
mkdir -p "$STATE_DIR" 2>/dev/null || exit 0

_bump_stat() {
    local bucket="$1"
    local lock="${STATS_FILE}.lock"
    (
        # 2s timeout — stats are best-effort, never block the user.
        flock -x -w 2 9 || return 0
        if [ ! -f "$STATS_FILE" ]; then
            printf '{"scanned":0,"drift_clean":0,"drift_found":0,"skipped_no_lock":0,"rejected_path":0,"bypass":0}\n' \
                > "$STATS_FILE"
        fi
        # mktemp instead of $$ to avoid PID collisions across long-running
        # subshells (debt-detector A4 from @code-critic).
        local tmp
        tmp=$(mktemp "${STATS_FILE}.tmp.XXXXXX" 2>/dev/null) || return 0
        if jq --arg b "$bucket" '.[$b] = (.[$b] // 0) + 1' "$STATS_FILE" > "$tmp" 2>/dev/null; then
            mv -f "$tmp" "$STATS_FILE"
        else
            rm -f "$tmp"
        fi
    ) 9> "$lock"
    return 0
}

if [ "${ARCA_SPEC_DRIFT_BYPASS:-0}" = "1" ]; then
    {
        printf '%s\t%s\tbypass=ARCA_SPEC_DRIFT_BYPASS=1\n' \
            "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${CLAUDE_SESSION_ID:-unknown}"
    } >> "$AUDIT_LOG" 2>/dev/null || true
    _bump_stat bypass
    exit 0
fi

# ---- Locate the repo to scan ----------------------------------------------
REPO=""
if [ -n "${ARCA_SPEC_DRIFT_REPO_HINT:-}" ] && [ -d "${ARCA_SPEC_DRIFT_REPO_HINT:-}" ]; then
    REPO="${ARCA_SPEC_DRIFT_REPO_HINT:-}"
else
    REPO="$(git rev-parse --show-toplevel 2>/dev/null || true)"
fi
[ -z "$REPO" ] && exit 0
[ ! -d "${REPO}/docs/specs" ] && exit 0

# ---- _sha256: portable SHA256 helper --------------------------------------
_sha256() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{print $1}'
    else
        echo ""
    fi
}

# ---- Walk every bundle -----------------------------------------------------
DRIFT_REPORT=""
DRIFT_FOUND_OVERALL=0

for BUNDLE in "${REPO}/docs/specs"/*/; do
    [ -d "$BUNDLE" ] || continue
    LOCK="${BUNDLE}spec.lock.json"
    if [ ! -f "$LOCK" ]; then
        _bump_stat skipped_no_lock
        continue
    fi

    if ! jq empty "$LOCK" 2>/dev/null; then
        _bump_stat skipped_no_lock
        continue
    fi

    _bump_stat scanned
    BUNDLE_DRIFT=0
    BUNDLE_NAME=$(basename "$BUNDLE")
    BUNDLE_REAL=$(realpath -m "$BUNDLE" 2>/dev/null)
    [ -z "$BUNDLE_REAL" ] && continue

    # L1 (jq whitelist): only file keys matching the safe regex pass.
    # `select(.key | test(...))` filters at extraction time. Anything
    # rejected here never reaches the bash loop — minimal attack surface.
    while IFS=$'\t' read -r FNAME EXPECTED; do
        [ -z "$FNAME" ] && continue

        # L2 (bash defence in depth): re-apply the same whitelist regex
        # jq already enforces. Belt+suspenders — if jq is silently broken
        # by an unexpected jq version (filter compiled but not applied)
        # this catches any non-conforming key. Using [[ =~ ]] over case
        # globs because globs interpret . as literal but treat patterns
        # like *..* and *$'\n'* inconsistently across bash 3 / 4 / 5
        # under different `shopt` settings — observed false-positive on
        # plain "requirements.md" during ciclo 2 re-test.
        if [[ ! "$FNAME" =~ ^[a-zA-Z0-9._-]+\.(md|yaml|yml|json)$ ]]; then
            _bump_stat rejected_path
            BUNDLE_DRIFT=1
            DRIFT_REPORT="${DRIFT_REPORT}  ${BUNDLE_NAME}/<rejected-path>: REJECTED (suspicious filename in lock)
"
            continue
        fi

        TARGET="${BUNDLE}${FNAME}"
        TARGET_REAL=$(realpath -m "$TARGET" 2>/dev/null)
        if [ -z "$TARGET_REAL" ]; then
            _bump_stat rejected_path
            BUNDLE_DRIFT=1
            DRIFT_REPORT="${DRIFT_REPORT}  ${BUNDLE_NAME}/${FNAME}: REJECTED (path resolution failed)
"
            continue
        fi

        # L3 (realpath containment): TARGET_REAL must be under BUNDLE_REAL.
        # Closes symlink escape too (lock says "innocent.md", FS has a
        # symlink innocent.md → /etc/passwd).
        case "$TARGET_REAL" in
            "${BUNDLE_REAL}"/*) ;;
            *)
                _bump_stat rejected_path
                BUNDLE_DRIFT=1
                DRIFT_REPORT="${DRIFT_REPORT}  ${BUNDLE_NAME}/<rejected-path>: REJECTED (escapes bundle dir)
"
                continue
                ;;
        esac

        if [ ! -f "$TARGET_REAL" ]; then
            BUNDLE_DRIFT=1
            DRIFT_REPORT="${DRIFT_REPORT}  ${BUNDLE_NAME}/${FNAME}: MISSING (was ${EXPECTED:0:12}…)
"
            continue
        fi

        ACTUAL=$(_sha256 "$TARGET_REAL")
        if [ -z "$ACTUAL" ]; then
            # No sha256sum/shasum on host. Cannot verify; silent skip.
            continue
        fi
        if [ "$EXPECTED" != "$ACTUAL" ]; then
            BUNDLE_DRIFT=1
            DRIFT_REPORT="${DRIFT_REPORT}  ${BUNDLE_NAME}/${FNAME}: drift
    expected ${EXPECTED:0:12}…
    actual   ${ACTUAL:0:12}…
"
        fi
    done < <(jq -r '.files // {}
                    | to_entries[]
                    | select(.key | test("^[a-zA-Z0-9._-]+\\.(md|yaml|yml|json)$"))
                    | "\(.key)\t\(.value)"' "$LOCK" 2>/dev/null)

    # Detect entries that jq dropped due to whitelist — they need to be
    # counted as rejected even though we did not loop over them.
    REJECTED_BY_JQ=$(jq -r '
        (.files // {}) as $f
        | ($f | length) as $total
        | ($f | to_entries
              | map(select(.key | test("^[a-zA-Z0-9._-]+\\.(md|yaml|yml|json)$")))
              | length) as $kept
        | $total - $kept' "$LOCK" 2>/dev/null)
    if [ -n "$REJECTED_BY_JQ" ] && [ "$REJECTED_BY_JQ" -gt 0 ] 2>/dev/null; then
        BUNDLE_DRIFT=1
        for _ in $(seq 1 "$REJECTED_BY_JQ"); do
            _bump_stat rejected_path
        done
        DRIFT_REPORT="${DRIFT_REPORT}  ${BUNDLE_NAME}/<${REJECTED_BY_JQ}-rejected>: REJECTED by jq whitelist
"
    fi

    if [ "$BUNDLE_DRIFT" -eq 1 ]; then
        _bump_stat drift_found
        DRIFT_FOUND_OVERALL=1
    else
        _bump_stat drift_clean
    fi
done

# ---- Emit advisory nudge if any drift detected ----------------------------
if [ "$DRIFT_FOUND_OVERALL" -eq 1 ]; then
    {
        echo ""
        echo "[spec-drift-detector] ADVISORY: SDD bundle drift detected"
        echo "  ADR-028 spec.lock.json fingerprints diverge from current files."
        echo ""
        printf '%s' "$DRIFT_REPORT"
        echo ""
        echo "  Why this matters:"
        echo "    • The lock is the contract auditors read (EU AI Act, SOC 2)."
        echo "    • A REJECTED entry indicates a malformed or malicious lock."
        echo "    • A drift means spec.md was edited without re-fingerprint."
        echo ""
        echo "  How to resolve:"
        echo "    1. Confirm the spec changes are intentional."
        echo "    2. Re-fingerprint:  cd <bundle> && for f in *.md; do"
        echo "                            sha256sum \"\$f\"; done"
        echo "       Update spec.lock.json .files entries with the new hashes."
        echo "    3. If REJECTED: inspect the lock, never accept paths with"
        echo "       /, .., or extensions outside {md,yaml,yml,json}."
        echo "    4. Commit lock + spec together (atomic)."
        echo ""
        echo "  Bypass once (audit-logged):  ARCA_SPEC_DRIFT_BYPASS=1 git push"
        echo "  This hook is ADVISORY for 30 days (ADR-027 S6 reviews promotion)."
        echo ""
    } >&2
fi

exit 0
