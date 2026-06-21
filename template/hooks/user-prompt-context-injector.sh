#!/usr/bin/env bash
# ARCA — UserPromptSubmit context injector
#
# Se dispara ANTES de que el modelo vea el prompt del usuario. Inyecta
# contexto dinámico que reduce fricción "Claude no sabe qué estaba
# haciendo" al principio de cada turno.
#
# Inspirado en rohitg00/awesome-claude-code-toolkit "UserPromptSubmit hook
# inject context (time, idle duration, project state)".
#
# El runtime envía por stdin un JSON con al menos:
#   { "prompt": "<texto>", "cwd": "...", "session_id": "..." }
#
# Si el hook escribe a stdout una cadena, se añade como prefix al prompt
# antes de pasarlo al modelo. Política:
#   - Output conciso (<600 chars) para no gastar tokens.
#   - Solo datos observables (git, fs). NO llamadas de red ni MCPs.
#   - Nunca bloquea — exit 0 siempre, incluso si hay errores.
#   - Se skippea si el prompt empieza por "/" (slash command) — ya tiene contexto.

set -uo pipefail

payload="$(cat -)"

# Extract prompt text + transcript_path + session_id (jq opcional — fallback vacío)
if command -v jq >/dev/null 2>&1; then
    prompt=$(printf '%s' "${payload}" | jq -r '.prompt // empty' 2>/dev/null || echo "")
    cwd=$(printf '%s' "${payload}" | jq -r '.cwd // empty' 2>/dev/null || echo "${PWD}")
    transcript_path=$(printf '%s' "${payload}" | jq -r '.transcript_path // empty' 2>/dev/null || echo "")
    session_id=$(printf '%s' "${payload}" | jq -r '.session_id // empty' 2>/dev/null || echo "")
else
    prompt=""
    cwd="${PWD}"
    transcript_path=""
    session_id=""
fi

# Skip si es slash command (ya tiene contexto propio)
if [[ "${prompt}" =~ ^/[a-z] ]]; then
    exit 0
fi

# Skip si el prompt es muy corto (conversacional — no inflar con contexto)
if [[ "${#prompt}" -lt 30 ]]; then
    exit 0
fi

out_lines=()

# 1. Idle time desde último turno — leemos marker file
idle_file="${HOME}/.claude/state/last-turn-timestamp"
mkdir -p "$(dirname "${idle_file}")"
if [[ -f "${idle_file}" ]]; then
    last_ts=$(cat "${idle_file}" 2>/dev/null || echo 0)
    now_ts=$(date +%s)
    idle_sec=$((now_ts - last_ts))
    if (( idle_sec > 3600 )); then
        out_lines+=("[contexto] sesión retomada tras $(( idle_sec / 3600 ))h inactivo — revisa estado del trabajo pendiente.")
    elif (( idle_sec > 600 )); then
        out_lines+=("[contexto] $(( idle_sec / 60 )) min desde último turno.")
    fi
fi
date +%s > "${idle_file}"

# 2. Git state: uncommitted work + branch actual (solo si es repo)
cd "${cwd}" 2>/dev/null || true
if git rev-parse --show-toplevel >/dev/null 2>&1; then
    branch=$(git branch --show-current 2>/dev/null || echo "detached")
    uncommitted=$(git status --porcelain 2>/dev/null | wc -l)
    ahead_behind=$(git rev-list --left-right --count "@{u}...HEAD" 2>/dev/null || echo "")
    summary="[git] rama: ${branch}"
    if (( uncommitted > 0 )); then
        summary+=" · ${uncommitted} archivo(s) sin commitear"
    fi
    if [[ -n "${ahead_behind}" ]]; then
        behind=$(echo "${ahead_behind}" | awk '{print $1}')
        ahead=$(echo "${ahead_behind}" | awk '{print $2}')
        if (( ahead > 0 )); then summary+=" · ${ahead} commit(s) sin push"; fi
        if (( behind > 0 )); then summary+=" · ${behind} commit(s) behind remote"; fi
    fi
    out_lines+=("${summary}")
fi

# 3. Último commit (contexto de continuidad)
if git rev-parse HEAD >/dev/null 2>&1; then
    last_commit=$(git log -1 --pretty=format:'%h · %s' 2>/dev/null || echo "")
    if [[ -n "${last_commit}" ]]; then
        out_lines+=("[último commit] ${last_commit}")
    fi
fi

# 4. Auto-tune pending desde telemetry (si existe marker)
autotune_marker="${HOME}/.claude/state/autotune-pending.txt"
if [[ -s "${autotune_marker}" ]]; then
    agents=$(head -c 200 "${autotune_marker}" | tr '\n' ' ')
    out_lines+=("[auto-tune] agentes con feedback pendiente: ${agents}")
fi

# 5. Task tracker activo (si hay task file en el project)
task_file=".claude/state/current-task.md"
if [[ -f "${task_file}" ]]; then
    task=$(head -1 "${task_file}" 2>/dev/null | head -c 120)
    if [[ -n "${task}" ]]; then
        out_lines+=("[tarea en curso] ${task}")
    fi
fi

# 6. Context window monitor (ADR-039) — warn at threshold (default 40%).
# Rate-limited to one warning per session; bypass via ARCA_CONTEXT_MONITOR_DISABLE=1.
if [[ "${ARCA_CONTEXT_MONITOR_DISABLE:-0}" != "1" && -n "${transcript_path}" && -f "${transcript_path}" ]]; then
    estimator_lib="${HOME}/.claude/hooks/lib/context-window-estimator.sh"
    if [[ -f "${estimator_lib}" ]]; then
        # shellcheck source=/dev/null
        . "${estimator_lib}"
        ctx_pct=$(context_estimate_pct "${transcript_path}")
        threshold=$(context_threshold_pct)
        warn_marker="${HOME}/.claude/state/context-monitor-warned-${session_id:-nosess}"
        if (( ctx_pct >= threshold )) && [[ ! -f "${warn_marker}" ]]; then
            window=$(context_window_size)
            tokens=$(context_estimate_tokens "${transcript_path}")
            out_lines+=("[contexto-window] ~${ctx_pct}% de ${window} tokens (~${tokens} usados) — considera /compact (ADR-039 threshold ${threshold}%)")
            : > "${warn_marker}"
        fi
    fi
fi

# Si hay algo útil que decir, emitir como bloque prefixado al prompt
if [[ ${#out_lines[@]} -gt 0 ]]; then
    printf '<arca-context>\n'
    for line in "${out_lines[@]}"; do
        printf '  %s\n' "${line}"
    done
    printf '</arca-context>\n\n'
fi

exit 0
