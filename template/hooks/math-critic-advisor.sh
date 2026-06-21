#!/bin/bash
# PostToolUse hook: detecta ediciones en .py con patrones ML/DL/AI
# y emite WARNING a stderr recomendando invocar @math-critic.
# No bloquea (exit 0 siempre) — es solo advisory.

set -uo pipefail

INPUT=$(cat 2>/dev/null || echo '{}')

# Extraer path del archivo editado
FILE_PATH=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    t = d.get('tool_input', d)
    # Edit/Write tienen file_path, MultiEdit también
    print(t.get('file_path', ''))
except Exception:
    print('')
" 2>/dev/null)

# Solo actuar sobre archivos .py
if [[ ! "$FILE_PATH" =~ \.py$ ]]; then
    exit 0
fi

# Solo si el archivo existe (post-edit)
if [ ! -f "$FILE_PATH" ]; then
    exit 0
fi

# Patrones matemáticos que disparan recomendación
ML_PATTERNS='import torch|import torch\.nn|from torch|import numpy|import sklearn|from sklearn|import scipy|from scipy\.stats|import statsmodels|torch\.nn\.functional|F\.cross_entropy|F\.softmax|F\.log_softmax|nn\.CrossEntropy|nn\.BCE|nn\.MSE|\.backward\(|optim\.|loss_fn|loss =|gradient|grad_norm'

if grep -qE "$ML_PATTERNS" "$FILE_PATH" 2>/dev/null; then
    # Marker local para evitar spam — una sola recomendación por archivo y día
    STATE_DIR="${HOME}/.claude/state/math-critic-advised"
    mkdir -p "$STATE_DIR"
    MARKER="${STATE_DIR}/$(echo "$FILE_PATH" | md5sum | cut -c1-16)-$(date +%Y%m%d)"

    if [ ! -f "$MARKER" ]; then
        touch "$MARKER"
        cat >&2 <<EOF
[MATH-CRITIC ADVISOR] Detectadas operaciones matemáticas en ${FILE_PATH}.

Si este código proviene de @ml-engineer, @dl-engineer o @ai-engineer, debes invocar @math-critic ANTES de @code-critic.

Cadena correcta: agente → @math-critic → @debt-detector → @code-critic.

Referencia: ~/.claude/agents/math-critic.md sección "Triggers".
EOF
    fi
fi

exit 0
