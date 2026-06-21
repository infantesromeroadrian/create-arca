---
description: Open the Q&A REPL backed by Ollama Qwen with the live transcript as context. Loads system prompt from prompts/generic.md by default; override with --prompt path. Usage `/ask-live [--prompt path]`.
allowed-tools: Bash(~/.claude/skills/live-transcribe/scripts/ask.sh*), Bash(bash*)
---

Lanza el REPL Q&A. Cada pregunta lee el transcript live (`/tmp/live-transcript.txt`) en tiempo real y consulta a Ollama Qwen.

Comandos dentro del REPL:
- `/tail` — muestra las últimas 30 líneas del transcript
- `/clear` — resetea el historial de conversación
- `Ctrl+C` — salir

## Comando ejecutable

```bash
bash ~/.claude/skills/live-transcribe/scripts/ask.sh "$@"
```

## Para una reunión específica con prompt custom

```bash
/ask-live --prompt ~/.claude/skills/live-transcribe/scripts/prompts/my-meeting.md
# o vía env var:
LT_PROMPT_FILE=~/.claude/skills/live-transcribe/scripts/prompts/my-meeting.md /ask-live
```

Los prompts custom (cualquier `prompts/*.md` que no sea `generic.md` o `example-*.md`) están gitignored por defecto: pensados para llevar contexto sensible de la reunión sin riesgo de que se filtren al repo.
