#!/usr/bin/env bash
# skills/adr-new/run.sh — Auto-ADR (E.2) executable core.
#
# Single source of truth for /adr-new behavior. The slash command and the
# SKILL.md page are thin pointers: both invoke this script with the raw
# title as $1, which keeps $ARGUMENTS out of any context that bash would
# re-evaluate. Splitting the executable from the markdown also closes the
# duplication flagged by @code-critic (advertencia A-4).
#
# Args:
#   $1 — raw title (literal). Empty or <5 trimmed chars aborts.
#
# Exit codes:
#   0  success — ADR file created at docs/adr/NNN-slug.md
#   1  user-facing validation error (empty / too short / slug empty / ...)
#   2  environment error (no docs/adr, no template)
#
# Side effects:
#   - Creates docs/adr/NNN-slug.md (never overwrites).
#   - Touches docs/adr/.adr-numbering.lock for the flock critical section.
#   - Increments ~/.claude/state/auto-adr-stats.json drafted_via_skill.

set -uo pipefail

# Defense in depth (ARCA-SEC-1 B1, cycle 4): the slash-command and skill
# bash blocks always invoke run.sh with the title as a single argv slot.
# Anything else means the caller block was tampered or a parallel/manual
# invocation broke the contract — refuse rather than guess.
if [[ $# -ne 1 ]]; then
    echo "[/adr-new run.sh] expects exactly 1 argv (title); got $#." >&2
    exit 2
fi

TITLE_RAW="$1"

if [ -z "$TITLE_RAW" ]; then
    echo "[/adr-new] ERROR: titulo vacio. Uso: /adr-new <titulo corto>" >&2
    echo "Ejemplo: /adr-new langgraph-state-checkpointing" >&2
    exit 1
fi

TITLE_TRIMMED="$(printf '%s' "$TITLE_RAW" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

if [ "${#TITLE_TRIMMED}" -lt 5 ]; then
    echo "[/adr-new] ERROR: titulo demasiado corto (${#TITLE_TRIMMED} chars, minimo 5)." >&2
    echo "Da contexto. '/adr-new fastapi-async-routing' es mejor que '/adr-new fix'." >&2
    exit 1
fi

# Slug: lowercase, non-alnum collapsed to single dash, edges trimmed.
SLUG=$(printf '%s' "$TITLE_TRIMMED" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g' \
    | sed -E 's/^-+|-+$//g' \
    | sed -E 's/-+/-/g')

if [ -z "$SLUG" ]; then
    echo "[/adr-new] ERROR: slug vacio tras sanitizar. Usa palabras alfanumericas." >&2
    exit 1
fi

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-${PWD}}"
ADR_DIR="${PROJECT_DIR}/docs/adr"
TPL="${PROJECT_DIR}/skills/adr-new/template.md"
LOCK="${ADR_DIR}/.adr-numbering.lock"

if [ ! -d "$ADR_DIR" ]; then
    echo "[/adr-new] ERROR: no existe $ADR_DIR" >&2
    echo "Crea el directorio con README.md primero, o asegurate de que CLAUDE_PROJECT_DIR apunta al sitio correcto." >&2
    exit 2
fi

if [ ! -f "$TPL" ]; then
    echo "[/adr-new] ERROR: plantilla no encontrada: $TPL" >&2
    exit 2
fi

# Critical section: serialize numbering against parallel /adr-new calls.
exec 9>"$LOCK"
flock -x 9

NEXT_N=$(ls "$ADR_DIR" 2>/dev/null \
    | grep -oE '^[0-9]{3}' \
    | sort -n \
    | tail -1)

if [ -z "$NEXT_N" ]; then
    NEXT_N=1
else
    NEXT_N=$((10#$NEXT_N + 1))
fi

NNN=$(printf '%03d' "$NEXT_N")
TARGET="${ADR_DIR}/${NNN}-${SLUG}.md"

if [ -e "$TARGET" ]; then
    echo "[/adr-new] ERROR: ya existe ${TARGET}. Elige otro slug o renombra el ADR previo." >&2
    flock -u 9
    exit 1
fi

DATE_ISO=$(date -I)
TPL_BODY=$(cat "$TPL")

# Render template. Two pitfalls forced this shape:
#   - awk gsub treats `&` in the replacement as the matched text, so a
#     title containing "&" would emit the placeholder back. We replace
#     the title via index/substr instead of gsub to dodge it entirely.
#   - awk -v interprets backslash escapes (\n, \t, \b...). We pass the
#     title through ENVIRON to keep the raw bytes intact.
RENDERED=$(printf '%s' "$TPL_BODY" \
    | sed "s/{{NNN}}/${NNN}/g" \
    | sed "s/{{DATE}}/${DATE_ISO}/g" \
    | ARCA_ADR_TITLE="$TITLE_TRIMMED" awk '
        BEGIN { needle = "{{TITLE}}"; t = ENVIRON["ARCA_ADR_TITLE"]; nlen = length(needle) }
        {
            line = $0
            out = ""
            while ((p = index(line, needle)) > 0) {
                out = out substr(line, 1, p - 1) t
                line = substr(line, p + nlen)
            }
            print out line
        }
    ')

if ! printf '%s\n' "$RENDERED" > "$TARGET" 2>/dev/null; then
    echo "[/adr-new] ERROR: no se pudo escribir $TARGET" >&2
    echo "  Causa probable: titulo demasiado largo (ENAMETOOLONG) o filesystem read-only." >&2
    flock -u 9
    exit 2
fi

flock -u 9

bash "${PROJECT_DIR}/hooks/lib/auto-adr-stats.sh" drafted_via_skill 2>/dev/null || true

echo "[/adr-new] Creado: ${TARGET}"
echo
echo "Proximos pasos:"
echo "  1. Rellena Context / Decision / Rationale / Consequences."
echo "  2. Anade la fila en docs/adr/README.md indice."
echo "  3. (Opcional) bash hooks/lib/adr-judge.sh ${TARGET}"
echo "  4. /justify '<intencion>' antes del commit que rellena las secciones."
