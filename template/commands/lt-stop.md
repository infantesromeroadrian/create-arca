---
description: Stop the live transcription pipeline. Kills transcribe.py + parec processes started by /lt-start. Idempotent.
allowed-tools: Bash(pkill*), Bash(pgrep*), Bash(sleep*), Bash(echo*)
---

Para los procesos del pipeline de transcripción en directo. Idempotente — si nada está corriendo, no rompe.

## Comando ejecutable

```bash
pkill -f "transcribe.py" 2>/dev/null
pkill -f "^parec.*monitor" 2>/dev/null
sleep 1
if pgrep -f "transcribe.py" > /dev/null; then
    echo "[/lt-stop] still alive, escalating to SIGKILL..."
    pkill -9 -f "transcribe.py" 2>/dev/null
    pkill -9 parec 2>/dev/null
fi
echo "[/lt-stop] stopped."
```

Se invoca antes de `/lt-archive` (el archivador refusa correr si transcribe.py sigue vivo, para no leer el transcript a medio escribir).
