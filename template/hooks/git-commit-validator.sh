#!/bin/bash
# PreToolUse hook: valida conventional commits en `git commit -m "..."`.
# Bloquea (exit 2) si el mensaje no cumple formato.
# Permite (exit 0) si la operación no es un commit o si cumple.

set -uo pipefail

# Stats helper (Task #50 ADV-1) — observability over the skip/block/pass split.
# `bump_and_exit` is the canonical exit path for this hook: it records the
# bucket reason before exiting so we can see if operators are leaning on the
# substitution / HEREDOC fail-safe instead of writing conventional commits.
# Sourced from the project repo when running in dev, from ~/.claude/hooks/lib
# when running under the deployed harness (the runtime-sync rule keeps both
# copies identical).
STATS_HELPER_DEV="$(dirname "$0")/lib/git-commit-validator-stats.sh"
STATS_HELPER_RUNTIME="${HOME}/.claude/hooks/lib/git-commit-validator-stats.sh"
bump_and_exit() {
    local bucket="$1"
    local code="$2"
    if [[ -x "$STATS_HELPER_DEV" ]]; then
        bash "$STATS_HELPER_DEV" "$bucket" 2>/dev/null || true
    elif [[ -x "$STATS_HELPER_RUNTIME" ]]; then
        bash "$STATS_HELPER_RUNTIME" "$bucket" 2>/dev/null || true
    fi
    exit "$code"
}

# Force UTF-8 locale for embedded python3 (Task #50 ADV-3). Without this, a
# minimal locale (LC_ALL=C) causes `json.load` to fail on non-ASCII bytes
# (emoji, accented chars) -> CMD ends empty -> hook exits 0 silently. The
# override is local to this subshell so it does not leak.
PY3_UTF8=(env LC_ALL=en_US.UTF-8 python3)

# Leer tool input desde stdin (formato hooks v2+)
INPUT=$(cat 2>/dev/null || echo '{}')

# Extraer comando bash — soporta tanto stdin JSON como env TOOL_INPUT legacy
CMD=$(echo "$INPUT" | "${PY3_UTF8[@]}" -c "
import sys, json
try:
    d = json.load(sys.stdin)
    tool = d.get('tool_input', d)
    print(tool.get('command', ''))
except Exception:
    print('')
" 2>/dev/null)

# Fallback legacy
if [ -z "$CMD" ] && [ -n "${TOOL_INPUT:-}" ]; then
    CMD=$(echo "$TOOL_INPUT" | "${PY3_UTF8[@]}" -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('command', ''))
except Exception:
    print('')
" 2>/dev/null)
fi

# Solo actuar sobre git commit con mensaje inline (-m)
if ! echo "$CMD" | grep -qE '^[[:space:]]*git[[:space:]]+commit[[:space:]]+.*-m[[:space:]]'; then
    bump_and_exit "skip_non_commit" 0
fi

# Permitir --amend sin mensaje (solo reescribe autor o timestamp)
if echo "$CMD" | grep -qE -- '--amend([[:space:]]|$)' && ! echo "$CMD" | grep -qE -- '-m[[:space:]]'; then
    bump_and_exit "skip_amend" 0
fi

# Extraer mensaje: soporta -m "msg", -m 'msg', --message="msg"
MSG=$(echo "$CMD" | "${PY3_UTF8[@]}" -c "
import sys, re, shlex
cmd = sys.stdin.read()
try:
    tokens = shlex.split(cmd)
except ValueError:
    print('')
    sys.exit(0)
msg = ''
i = 0
while i < len(tokens):
    t = tokens[i]
    if t in ('-m', '--message') and i + 1 < len(tokens):
        msg = tokens[i+1]
        break
    if t.startswith('--message='):
        msg = t.split('=', 1)[1]
        break
    i += 1
print(msg)
" 2>/dev/null)

if [ -z "$MSG" ]; then
    # No pudimos parsear — no bloqueamos, dejamos pasar
    bump_and_exit "skip_no_message" 0
fi

# Skip validation when the extracted message looks like an unexpanded shell
# construct that the shell will resolve at runtime (Task #49):
#   - $(...)            command substitution
#   - `...`             backtick command substitution
#   - ${...}            parameter expansion (Task #50 ADV-4)
#   - <<EOF / <<-EOF    HEREDOC marker (anchored to start of MSG, Task #50 ADV-2)
# shlex.split returns the literal pre-expansion token, so the "subject" extracted
# here is the substitution marker itself (e.g. "$(cat <<'EOF'") rather than the
# real commit message. Validating that literal produces a false-positive block.
# Fail-safe to skip: the validator is preventive, not authoritative.
#
# Note on the HEREDOC anchor (Task #50 ADV-2): the original pattern matched
# `<<EOF` anywhere in MSG. A legitimate commit like "feat(parser): support
# <<EOF tokens" was therefore skipped silently. With `^<<` the skip only fires
# when MSG itself *begins* with the HEREDOC marker — the only shape where
# shlex extracted a marker as the "message" rather than the expanded body.
SUBSTITUTION_SKIP_REGEX='^\$\(|^`|^\$\{|^<<-?[A-Za-z_'\'']'
if echo "$MSG" | grep -qE "$SUBSTITUTION_SKIP_REGEX"; then
    echo "[GIT-MASTER] Commit message uses shell substitution or HEREDOC — conventional commit validator skipped (see hooks/git-commit-validator.sh:SUBSTITUTION_SKIP_REGEX)." >&2
    # Split the bucket so the metric distinguishes substitution from HEREDOC.
    case "$MSG" in
        \$\(*|\`*|\$\{*) bump_and_exit "skip_substitution" 0 ;;
        *)               bump_and_exit "skip_heredoc"      0 ;;
    esac
fi

# Primera línea = subject
SUBJECT=$(echo "$MSG" | head -1)

# Regex conventional commits: type(scope): description
# Types permitidos según git-master.md v2.0.0
CONVENTIONAL_REGEX='^(feat|fix|refactor|docs|test|ci|perf|experiment|chore|style|build|revert)(\([a-z0-9_-]+\))?!?: [a-z].+[^.]$'

if echo "$SUBJECT" | grep -qE "$CONVENTIONAL_REGEX"; then
    # Validación adicional: longitud subject <72 chars
    LEN=${#SUBJECT}
    if [ "$LEN" -gt 72 ]; then
        cat >&2 <<EOF
[GIT-MASTER] Commit RECHAZADO — subject demasiado largo

Mensaje: "$SUBJECT"
Longitud: $LEN caracteres (máximo 72)

Regla violada: convención conventional commits limita la primera línea a 72 chars para legibilidad en git log, herramientas de CI y GitHub.

Corrección: acorta la descripción o mueve detalles al body del commit con -m "<body>" adicional.
EOF
        bump_and_exit "block_length" 2
    fi
    bump_and_exit "pass_conventional" 0
fi

# No cumple formato — bloquear con mensaje educativo
cat >&2 <<EOF
[GIT-MASTER] Commit RECHAZADO — formato no convencional

Mensaje recibido: "$SUBJECT"

Formato obligatorio:
  <type>(<scope>): <descripción imperativa minúscula sin punto final>

Types válidos:
  feat · fix · refactor · docs · test · ci · perf · experiment · chore · style · build · revert

Scopes ML comunes:
  model · pipeline · data · training · evaluation · deployment · monitoring · security · infra · api · frontend

Ejemplos aprobados:
  feat(monitoring): implement PSI-based drift detector
  fix(pipeline): handle null values in feature extraction
  refactor(training): extract validation loop to separate function
  docs(api): add endpoint examples to inference documentation

Reglas:
  - Subject ≤72 caracteres
  - Descripción en minúscula, imperativa, sin punto final
  - Un commit = un propósito atómico

Referencia: ~/.claude/agents/git-master.md sección "CONVENTIONAL COMMITS"
EOF
bump_and_exit "block_format" 2
