---
description: End-of-meeting archive. Reads /tmp/live-transcript.txt, copies it (raw + YAML frontmatter) to <vault>/Transcripciones-Reuniones/, generates a 5-7 bullet summary via Ollama, persists summary to Engram. Usage `/lt-archive [slug] [--project P] [--attendees A,B] [--keep] [--no-engram]`.
allowed-tools: Bash(~/.claude/skills/live-transcribe/scripts/lt_archive.py*), Bash(bash*), Bash(pgrep*)
---

Archiva el transcript actual al final de una reunión:
1. Verifica que `transcribe.py` NO esté corriendo (atomicidad — sino aborta).
2. Lee `/tmp/live-transcript.txt`.
3. Llama a Ollama Qwen para generar resumen ejecutivo de 5-7 bullets.
4. Escribe nota Markdown con YAML-safe frontmatter en `<vault>/Transcripciones-Reuniones/<YYYY-MM-DD>-<slug>.md`.
5. Persiste resumen en Engram (CLI) con tipo `meeting-summary` + cross-link al path Obsidian.
6. Borra `/tmp/live-transcript.txt` salvo `--keep`.

## Uso

```bash
/lt-archive onboarding-rrhh                                     # interactivo
/lt-archive onboarding-rrhh --project myproject --attendees "personA,personB"
/lt-archive onboarding-rrhh --no-engram                          # solo Obsidian
/lt-archive onboarding-rrhh --keep                               # preserva /tmp tras archivar
```

## Comando ejecutable

```bash
bash -c '
RUNTIME_DIR="${LT_RUNTIME_DIR:-$HOME/Code/live-transcribe}"
if [ ! -f "$RUNTIME_DIR/.venv/bin/activate" ]; then
    echo "Runtime venv not found at $RUNTIME_DIR/.venv. Bootstrap first (see /lt-start)."
    exit 1
fi
source "$RUNTIME_DIR/.venv/bin/activate"
export LT_RUNTIME_DIR="$RUNTIME_DIR"
cd "$HOME/.claude/skills/live-transcribe/scripts"
python lt_archive.py "$@"
' -- "$@"
```

## Garantías de atomicidad

- Si `transcribe.py` sigue vivo → aborta antes de leer (transcript podría estar a medio escribir).
- Si Ollama falla → el `/tmp/live-transcript.txt` queda preservado para reintento.
- Si Engram falla → el `.md` Obsidian ya está escrito, transcript también preservado.
- Solo borra `/tmp` cuando todo PASS y no se pasó `--keep`.
