---
description: Start live meeting transcription. Captures default PipeWire sink with parec, transcribes via faster-whisper on CUDA, appends to /tmp/live-transcript.txt. Background process. Stop with /lt-stop.
allowed-tools: Bash(~/.claude/skills/live-transcribe/scripts/start.sh*), Bash(nohup*), Bash(disown*), Bash(pgrep*), Bash(tail*), Bash(sleep*), Bash(echo*)
---

Arranca el pipeline de transcripción en directo en background.

## Proceso

1. Verifica que no haya otra instancia corriendo (`pgrep -f transcribe.py`).
2. Lanza `~/.claude/skills/live-transcribe/scripts/start.sh` con `nohup` + `disown` para que sobreviva al cierre del shell.
3. Redirige stderr a `/tmp/live-transcribe-stderr.log`.
4. Espera 6 s y confirma que `transcribe.py` está vivo (sino muestra las últimas 15 líneas del log).

## Comando ejecutable

```bash
if pgrep -f "transcribe.py" > /dev/null; then
    echo "[/lt-start] already running (PIDs: $(pgrep -f 'transcribe.py' | tr '\n' ' '))"
else
    nohup ~/.claude/skills/live-transcribe/scripts/start.sh > /tmp/live-transcribe-stderr.log 2>&1 &
    disown
    sleep 6
    if pgrep -f "transcribe.py" > /dev/null; then
        echo "[/lt-start] transcription started. Output: /tmp/live-transcript.txt"
    else
        echo "[/lt-start] startup failed. Last 15 lines of log:"
        tail -15 /tmp/live-transcribe-stderr.log
    fi
fi
```

## Output esperado

```
[/lt-start] transcription started. Output: /tmp/live-transcript.txt
```

Tras esto se puede `tail -f /tmp/live-transcript.txt` o invocar `/ask-live "pregunta"`.
