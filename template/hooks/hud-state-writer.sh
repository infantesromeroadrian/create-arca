#!/usr/bin/env bash
# ARCA — HUD state writer (PostToolUse).
#
# Escribe ~/.claude/hud.json con el estado live de la sesión para que
# waybar / cualquier status bar lo muestre. Idea de oh-my-claudecode
# (omc hud) adaptada a la stack Arch + Hyprland de ⟦ user_name ⟧.
#
# Formato JSON (estable — NO romper este schema sin actualizar waybar):
#   {
#     "ts": "2026-04-20T00:00:00+00:00",
#     "last_tool": "Edit",
#     "last_agent": null,
#     "cwd": "/home/.../.claude",
#     "git_branch": "main",
#     "uncommitted": 3,
#     "session_minutes": 42
#   }
#
# Política:
#   - Exit 0 siempre (nunca bloquea).
#   - Write atomic (tmp + mv) para evitar lectura parcial.
#   - Skip si la escritura anterior fue <2s atrás (rate limit —
#     sobre Write/Edit en ráfaga no tiene sentido actualizar cada).

set -uo pipefail

HUD_FILE="${HOME}/.claude/hud.json"
HUD_TMP="${HUD_FILE}.tmp.$$"
RATE_LIMIT_FILE="${HOME}/.claude/state/hud-last-write"
mkdir -p "$(dirname "${HUD_FILE}")" "$(dirname "${RATE_LIMIT_FILE}")"

now_epoch=$(date +%s)
if [[ -f "${RATE_LIMIT_FILE}" ]]; then
    last=$(cat "${RATE_LIMIT_FILE}" 2>/dev/null || echo 0)
    if (( now_epoch - last < 2 )); then
        exit 0
    fi
fi
echo "${now_epoch}" > "${RATE_LIMIT_FILE}"

payload="$(cat -)"
tool_name=""
cwd="${PWD}"
if command -v jq >/dev/null 2>&1; then
    tool_name=$(printf '%s' "${payload}" | jq -r '.tool_name // empty' 2>/dev/null || echo "")
    cwd=$(printf '%s' "${payload}" | jq -r '.cwd // empty' 2>/dev/null || echo "${PWD}")
fi

# Agent name si el PostToolUse es de Agent tool
last_agent="null"
if command -v jq >/dev/null 2>&1; then
    subagent=$(printf '%s' "${payload}" | jq -r '.tool_input.subagent_type // empty' 2>/dev/null || echo "")
    if [[ -n "${subagent}" ]]; then
        last_agent="\"${subagent}\""
    fi
fi

# Git state
branch="null"
uncommitted=0
if cd "${cwd}" 2>/dev/null && git rev-parse --show-toplevel >/dev/null 2>&1; then
    branch="\"$(git branch --show-current 2>/dev/null || echo detached)\""
    uncommitted=$(git status --porcelain 2>/dev/null | wc -l)
fi

# Session minutes: diferencia entre primer timestamp de la sesión y ahora
session_start_file="${HOME}/.claude/state/session-start-epoch"
if [[ -f "${session_start_file}" ]]; then
    session_start=$(cat "${session_start_file}" 2>/dev/null || echo "${now_epoch}")
else
    session_start="${now_epoch}"
    echo "${now_epoch}" > "${session_start_file}"
fi
session_min=$(( (now_epoch - session_start) / 60 ))

ts=$(date -Iseconds)

cat > "${HUD_TMP}" <<EOF
{
  "ts": "${ts}",
  "last_tool": "${tool_name}",
  "last_agent": ${last_agent},
  "cwd": "${cwd}",
  "git_branch": ${branch},
  "uncommitted": ${uncommitted},
  "session_minutes": ${session_min}
}
EOF

mv -f "${HUD_TMP}" "${HUD_FILE}"
exit 0
