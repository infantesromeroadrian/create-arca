#!/usr/bin/env bash
# skills/spec-new/run.sh — Spec-Driven Development bundle generator (ADR-027 S2).
#
# Single source of truth for /spec-new behavior. The slash command and the
# SKILL.md page are thin pointers: both invoke this script with the type and
# feature name as $1 and $2 respectively, keeping $ARGUMENTS out of any
# context that bash would re-evaluate.
#
# Args:
#   $1 — type. Must be in {api, ml, rag, agent}.
#   $2 — feature-name (raw). Sanitized to kebab-case slug. Min 5 chars trimmed.
#
# Exit codes:
#   0  success — bundle created at docs/specs/<slug>/
#   1  user-facing validation error (empty / too short / slug empty / type / collision)
#   2  environment error (no template, write failure, no docs/specs)
#
# Side effects:
#   - Creates docs/specs/<slug>/{requirements,design,tasks}.md
#   - Creates docs/specs/<slug>/spec.lock.json with SHA256 fingerprints
#   - Creates docs/specs/ + docs/specs/README.md if missing (with stub content)
#   - Increments ~/.claude/state/spec-new-stats.json (best-effort)

set -uo pipefail

# Defense in depth (ADR-007 / ARCA-SEC-1 B1 pattern, inherited from adr-new):
# expects exactly 2 argv slots. Anything else means caller block was tampered.
if [[ $# -ne 2 ]]; then
    echo "[/spec-new run.sh] expects exactly 2 argv (type + feature-name); got $#." >&2
    echo "Usage: bash run.sh <api|ml|rag|agent> <feature-name>" >&2
    exit 2
fi

TYPE_RAW="$1"
FEATURE_RAW="$2"

# ---- Validate type ----------------------------------------------------------
TYPE_TRIMMED="$(printf '%s' "$TYPE_RAW" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
case "$TYPE_TRIMMED" in
    api|ml|rag|agent) ;;
    "")
        echo "[/spec-new] ERROR: type vacio. Usa uno de: api ml rag agent." >&2
        echo "  Ejemplo: /spec-new api user-export-gdpr" >&2
        exit 1
        ;;
    *)
        echo "[/spec-new] ERROR: type '$TYPE_TRIMMED' no soportado." >&2
        echo "  Types validos: api, ml, rag, agent." >&2
        echo "  Frontend e infra reservados para fases posteriores (ADR-027 S6)." >&2
        exit 1
        ;;
esac

# ---- Validate + sanitize feature name --------------------------------------
FEATURE_TRIMMED="$(printf '%s' "$FEATURE_RAW" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
if [ -z "$FEATURE_TRIMMED" ]; then
    echo "[/spec-new] ERROR: feature-name vacio." >&2
    echo "  Uso: /spec-new <type> <feature-name>" >&2
    echo "  Ejemplo: /spec-new ml fraud-detection-classifier-v2" >&2
    exit 1
fi

# Length bounds (ADR-028 §"Threat Model" T-11 very-long-input + clarity).
# MIN: below this the slug loses descriptive value (e.g. "auth" → which auth?).
# MAX: hard cap before iconv allocates buffer — DoS guard at L0.
readonly MIN_FEATURE_LEN=5
readonly MAX_FEATURE_LEN=256

# ---- L0: length cap (ADR-028 layer L0) -------------------------------------
if [ "${#FEATURE_TRIMMED}" -gt "$MAX_FEATURE_LEN" ]; then
    echo "[/spec-new] ERROR: feature-name demasiado largo (${#FEATURE_TRIMMED} chars, max ${MAX_FEATURE_LEN})." >&2
    echo "  Acorta el nombre. Tip: el slug en disco es lo que verás durante meses." >&2
    exit 1
fi

if [ "${#FEATURE_TRIMMED}" -lt "$MIN_FEATURE_LEN" ]; then
    echo "[/spec-new] ERROR: feature-name demasiado corto (${#FEATURE_TRIMMED} chars, min ${MIN_FEATURE_LEN})." >&2
    echo "  Da contexto. 'fraud-detection' es mejor que 'fraud'." >&2
    exit 1
fi

# ---- L1-L5: defense-in-depth sanitize pipeline (ADR-028) -------------------
# Threat model and per-layer rationale documented in ADR-028 §"The Pipeline".
# Outsider-friendly summary: each stage neutralises a distinct adversarial
# class so a regression in one layer does not silently break the contract.
#
#   L1  LC_ALL=C tr -d '[:cntrl:]'
#       Strip ALL control bytes (\n, \t, \x00..\x1F, DEL) BEFORE iconv.
#       Closes B-3 from @code-critic ciclo 2: LC_ALL=C sed is line-oriented
#       so \n never enters the pattern space — controls had to be removed
#       upstream. Locale C forced for byte-level matching, avoids
#       multibyte-aware tr re-introducing surrogates.
#   L2  iconv -f UTF-8 -t ASCII//TRANSLIT//IGNORE
#       Best-effort UTF-8 → ASCII transliteration (é→e, ñ→n). //IGNORE drops
#       bytes with no ASCII equivalent (e.g. 你好 → "" not error). Wrapped
#       in `{ ... || cat; }` so a missing iconv binary degrades gracefully —
#       L4's byte-level sed still neutralises any surviving multibyte run.
#   L3  tr [:upper:] [:lower:]
#       Lowercase normalization AFTER L2 so "É" (already e from translit)
#       reaches lowercase consistently.
#   L4  LC_ALL=C sed -E 's/[^a-z0-9]+/-/g'
#       Byte-level whitelist + collapse runs of non-alnum to single dash.
#       LC_ALL=C is critical: under a UTF-8 locale, sed treats surviving
#       multibyte sequences as "letters" and preserves them.
#   L5  sed -E 's/^-+|-+$//g'
#       Trim leading/trailing dashes — slug must start and end alphanumeric.
SLUG=$(printf '%s' "$FEATURE_TRIMMED" \
    | LC_ALL=C tr -d '[:cntrl:]' \
    | { iconv -f UTF-8 -t ASCII//TRANSLIT//IGNORE 2>/dev/null || cat; } \
    | tr '[:upper:]' '[:lower:]' \
    | LC_ALL=C sed -E 's/[^a-z0-9]+/-/g' \
    | sed -E 's/^-+|-+$//g')

if [ -z "$SLUG" ]; then
    echo "[/spec-new] ERROR: slug vacio tras sanitizar. Usa palabras alfanumericas." >&2
    exit 1
fi

# ---- L6: post-condition tripwire (ADR-028) ---------------------------------
# Defense in depth — assert the slug matches our exact contract before any
# downstream component (mkdir, sed render, jq, lock filename) trusts it.
# Regex: only [a-z0-9-], must start AND end with alnum, length 1+. If this
# fires it means a layer above silently regressed (bug to fix, not bypass).
if ! printf '%s' "$SLUG" | LC_ALL=C grep -qE '^[a-z0-9]([a-z0-9-]*[a-z0-9])?$'; then
    echo "[/spec-new] FATAL: slug post-sanitize viola contrato regex." >&2
    echo "  Slug actual: '${SLUG}' (esperado: ^[a-z0-9]([a-z0-9-]*[a-z0-9])?\$)." >&2
    echo "  Esto es un bug en la pipeline de sanitize, no en tu input." >&2
    exit 2
fi

# ---- Locate paths -----------------------------------------------------------
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-${PWD}}"
SPECS_DIR="${PROJECT_DIR}/docs/specs"
SKILL_DIR="${HOME}/.claude/skills/spec-new"
TEMPLATES_DIR="${SKILL_DIR}/templates/${TYPE_TRIMMED}"
TARGET_DIR="${SPECS_DIR}/${SLUG}"
STATS_FILE="${HOME}/.claude/state/spec-new-stats.json"

# Verify templates exist for the requested type.
for f in requirements.md design.md tasks.md; do
    if [ ! -f "${TEMPLATES_DIR}/${f}" ]; then
        echo "[/spec-new] ERROR: plantilla no encontrada: ${TEMPLATES_DIR}/${f}" >&2
        echo "  Verifica que la skill esta instalada: ls ${SKILL_DIR}/templates/" >&2
        exit 2
    fi
done

# Bootstrap docs/specs/ if missing.
if [ ! -d "$SPECS_DIR" ]; then
    if ! mkdir -p "$SPECS_DIR" 2>/dev/null; then
        echo "[/spec-new] ERROR: no se pudo crear $SPECS_DIR" >&2
        exit 2
    fi
    cat > "${SPECS_DIR}/README.md" <<'README_EOF'
# Specs (Spec-Driven Development bundles)

Each subdirectory is a feature bundle generated by `/spec-new <type> <feature>`.
Per ADR-027, only features matching trigger rules R1-R4 land here. Fast-track
ARCA features stay in their cycle artefacts (Status.md, ADRs, code).

## Structure per feature

- `requirements.md` — what + why (user stories, acceptance criteria, NFRs)
- `design.md` — how (architecture, components, trade-offs, observability)
- `tasks.md` — sequenced steps with cycle mapping (C1-C14) and DoD per task
- `spec.lock.json` — SHA256 fingerprint of the 3 files; consumed by spec-drift-detector hook

## Triggers (ADR-027 §"Final scope")

| Rule | Test |
|---|---|
| R1 | API contract (OpenAPI / gRPC / MCP tool) |
| R2 | PII / GDPR Art 22 / EU AI Act / SOC 2 |
| R3 | ≥ 2 bounded contexts |
| R4 | C10 RTO ≤ 5 min AND user-facing |

If none → fast-track, no spec bundle.
README_EOF
fi

# ---- Helper: stats counter (best-effort, defined before first use) --------
_bump_stat() {
    local bucket="$1"
    local state_dir
    state_dir="$(dirname "$STATS_FILE")"
    mkdir -p "$state_dir" 2>/dev/null || return 0
    local lock="${STATS_FILE}.lock"
    (
        # Timeout 2s — if a previous run died holding the lock, fail loud
        # instead of hanging the user's terminal. Stats are best-effort.
        flock -x -w 2 9 || return 0
        if [ ! -f "$STATS_FILE" ]; then
            printf '{"created":0,"aborted_existing":0,"aborted_invalid_type":0,"aborted_invalid_args":0}\n' \
                > "$STATS_FILE"
        fi
        if command -v jq >/dev/null 2>&1; then
            # `local` would be a no-op inside this `( )` subshell — removed
            # per debt-detector finding. $$ is the parent shell PID, which
            # is unique per /spec-new invocation, so collisions across
            # parallel runs are impossible.
            tmp="${STATS_FILE}.tmp.$$"
            if jq --arg b "$bucket" '.[$b] = (.[$b] // 0) + 1' "$STATS_FILE" > "$tmp" 2>/dev/null; then
                mv -f "$tmp" "$STATS_FILE"
            else
                rm -f "$tmp"
            fi
        fi
    ) 9> "$lock"
    return 0
}

# ---- Atomic claim of TARGET_DIR (BLOCKER-1 race fix) -----------------------
# Without this lock, two parallel /spec-new with the same slug both pass the
# existence check below, both mkdir -p the same dir, and one's render-failure
# cleanup (rm -rf TARGET_DIR) clobbers the other's in-progress bundle.
# Reproduced by @code-critic test T4 — silent data loss with cryptic exit=2.
#
# The lockfile name is derived from the slug, not the bundle dir, so two
# distinct slugs do not block each other. The empty .lock file persists in
# docs/specs/ after exit (intentional): unlinking it would re-introduce a
# race when a parallel waiter still holds an FD on the now-deleted inode.
# Overhead is one inode per slug ever created — negligible.
SLUG_LOCK="${SPECS_DIR}/.${SLUG}.lock"
exec 9>"$SLUG_LOCK"
if ! flock -x -w 5 9; then
    echo "[/spec-new] ERROR: otra instancia esta creando bundle '${SLUG}'." >&2
    echo "  Espera unos segundos o borra ${SLUG_LOCK} si sospechas lock huerfano." >&2
    exit 1
fi
# Lock auto-released when FD 9 closes at script exit.

# Refuse overwrite — the spec bundle is append-only (ADR-027 §Consequences).
if [ -e "$TARGET_DIR" ]; then
    echo "[/spec-new] ERROR: ya existe ${TARGET_DIR}." >&2
    echo "  Para regenerar borralo manualmente: rm -rf ${TARGET_DIR}" >&2
    echo "  O elige otro slug (mejor: cambiar feature-name)." >&2
    _bump_stat "aborted_existing"
    exit 1
fi

# ---- Render templates ------------------------------------------------------
# date +%Y-%m-%d (POSIX) instead of date -I (GNU-only) for macOS/BSD parity,
# consistent with the sha256sum/shasum fallback below.
DATE_ISO=$(date +%Y-%m-%d)

if ! mkdir -p "$TARGET_DIR" 2>/dev/null; then
    echo "[/spec-new] ERROR: no se pudo crear $TARGET_DIR" >&2
    exit 2
fi

# Render placeholders. Same approach as adr-new: sed for {{NNN}}-style,
# awk via ENVIRON for arbitrary content (avoids gsub & ampersand pitfall).
_render_template() {
    local src="$1"
    local dst="$2"
    local body
    body=$(cat "$src")
    printf '%s' "$body" \
        | sed "s/{{TYPE}}/${TYPE_TRIMMED}/g" \
        | sed "s/{{DATE}}/${DATE_ISO}/g" \
        | sed "s/{{SLUG}}/${SLUG}/g" \
        | ARCA_FEATURE_NAME="$FEATURE_TRIMMED" awk '
            BEGIN { needle = "{{FEATURE}}"; t = ENVIRON["ARCA_FEATURE_NAME"]; nlen = length(needle) }
            {
                line = $0
                out = ""
                while ((p = index(line, needle)) > 0) {
                    out = out substr(line, 1, p - 1) t
                    line = substr(line, p + nlen)
                }
                print out line
            }
        ' > "$dst.tmp"
    if [ ! -s "$dst.tmp" ]; then
        rm -f "$dst.tmp"
        return 1
    fi
    mv -f "$dst.tmp" "$dst"
    return 0
}

for f in requirements.md design.md tasks.md; do
    if ! _render_template "${TEMPLATES_DIR}/${f}" "${TARGET_DIR}/${f}"; then
        echo "[/spec-new] ERROR: fallo renderizando ${f}" >&2
        # Cleanup partial render so user can retry without manual rm.
        rm -rf "$TARGET_DIR"
        exit 2
    fi
done

# ---- Compute SHA256 fingerprint --------------------------------------------
_sha256() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{print $1}'
    else
        echo "" # signal failure to caller
    fi
}

REQ_HASH=$(_sha256 "${TARGET_DIR}/requirements.md")
DES_HASH=$(_sha256 "${TARGET_DIR}/design.md")
TSK_HASH=$(_sha256 "${TARGET_DIR}/tasks.md")

if [ -z "$REQ_HASH" ] || [ -z "$DES_HASH" ] || [ -z "$TSK_HASH" ]; then
    echo "[/spec-new] ERROR: sha256sum/shasum no disponible. Lock file no creado." >&2
    rm -rf "$TARGET_DIR"
    exit 2
fi

# ---- Write spec.lock.json (atomic via tmp + rename) ------------------------
LOCK_TMP="${TARGET_DIR}/spec.lock.json.tmp.$$"
LOCK_FINAL="${TARGET_DIR}/spec.lock.json"

# Heredoc delimiter LOCK_EOF is intentionally NOT single-quoted so the
# interpolated values land in the JSON. Safety contract: every interpolated
# variable is locally controlled — SLUG (regex [a-z0-9-]), TYPE_TRIMMED
# (whitelist {api,ml,rag,agent}), DATE_ISO (date +%Y-%m-%d), *_HASH
# (sha256 hex, [0-9a-f]{64}). No user-supplied content reaches here without
# sanitize, so JSON injection is precluded by construction.
cat > "$LOCK_TMP" <<LOCK_EOF
{
  "version": "1.0",
  "feature": "${SLUG}",
  "type": "${TYPE_TRIMMED}",
  "created_at": "${DATE_ISO}",
  "files": {
    "requirements.md": "${REQ_HASH}",
    "design.md": "${DES_HASH}",
    "tasks.md": "${TSK_HASH}"
  },
  "related_adr": null,
  "triggers_fired": [],
  "drift_check": "advisory"
}
LOCK_EOF

# Validate JSON shape if jq available (defensive — if heredoc breaks, fail fast).
if command -v jq >/dev/null 2>&1; then
    if ! jq empty "$LOCK_TMP" 2>/dev/null; then
        echo "[/spec-new] ERROR: spec.lock.json renderizado invalido (JSON malformado)." >&2
        rm -f "$LOCK_TMP"
        rm -rf "$TARGET_DIR"
        exit 2
    fi
fi

mv -f "$LOCK_TMP" "$LOCK_FINAL"

_bump_stat "created"

# ---- User-facing summary ----------------------------------------------------
echo "[/spec-new] Bundle creado: ${TARGET_DIR}"
echo
echo "Archivos generados:"
echo "  ${TARGET_DIR}/requirements.md"
echo "  ${TARGET_DIR}/design.md"
echo "  ${TARGET_DIR}/tasks.md"
echo "  ${TARGET_DIR}/spec.lock.json"
echo
echo "Proximos pasos:"
echo "  1. Rellena las secciones marcadas <TODO: ...> en los 3 .md."
echo "  2. Linkea el ADR firmado: edita 'related_adr' en spec.lock.json y design.md."
echo "  3. Marca triggers_fired en spec.lock.json: ['R1'] o ['R2','R3'], etc."
echo "  4. Tras editar los .md: regenerar spec.lock.json a mano por ahora"
echo "     (sha256sum sobre los 3 ficheros; auto-rehash llega en S4 con spec-drift-detector.sh)."
echo "  5. /justify '<intencion del cambio>' antes del commit que rellena las secciones."
echo
echo "Recordatorio ADR-027: la spec NO duplica al ADR. Si el contenido es el mismo,"
echo "vive en el ADR y design.md linkea con [ADR-NNN](../../adr/NNN-slug.md)."

exit 0
