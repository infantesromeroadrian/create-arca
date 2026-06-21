#!/usr/bin/env bash
# Q&A REPL backed by Ollama. Reads the live Whisper transcript on every turn.
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")" && pwd)"
RUNTIME_DIR="${LT_RUNTIME_DIR:-$HOME/Code/live-transcribe}"

if [ ! -f "$RUNTIME_DIR/.venv/bin/activate" ]; then
    echo "[ask.sh] Runtime venv not found at $RUNTIME_DIR/.venv"
    echo "[ask.sh] See start.sh for bootstrap instructions."
    exit 1
fi
# shellcheck disable=SC1091
source "$RUNTIME_DIR/.venv/bin/activate"
export LT_RUNTIME_DIR="$RUNTIME_DIR"

cd "$SKILL_DIR"
exec python assistant.py "$@"
