---
name: live-transcribe
description: Live meeting transcription pipeline — captures the default PipeWire sink with parec, transcribes via faster-whisper on CUDA, exposes a Q&A REPL backed by local Ollama Qwen, and archives at end-of-meeting to Obsidian + Engram. 100% local. Activate when the user asks to "transcribir reunión", "live transcribe", "qué dijo en la reu", "graba esta reu", "archiva la reu", or invokes /lt-start, /lt-stop, /lt-archive, /ask-live.
---

# Live transcribe — skill scripts

This skill ships four scripts under `scripts/`:

| Script | Purpose |
|---|---|
| `start.sh` | Capture default PipeWire sink + faster-whisper (CUDA) → `/tmp/live-transcript.txt` |
| `transcribe.py` | Worker invoked by `start.sh` (reader thread + transcribe thread, drop-newest queue, append-mode resume) |
| `assistant.py` | REPL Q&A backed by Ollama; loads system prompt from `scripts/prompts/<name>.md` |
| `ask.sh` | Wrapper that activates venv and launches `assistant.py` |
| `lt_archive.py` | End-of-meeting archiver: Obsidian note (YAML-safe frontmatter) + Engram CLI |

## Runtime layout

The skill itself contains only source. Heavy binaries live outside:

```
~/.claude/skills/live-transcribe/scripts/   ← this directory (~28 KB)
~/Code/live-transcribe/.venv                ← Python venv (~2.5 GB) — bootstrap below
~/Code/live-transcribe/models               ← Whisper large-v3-turbo (~1.6 GB, auto-downloaded)
```

Override the runtime dir with `LT_RUNTIME_DIR=/path/to/runtime`.

## Bootstrap (one-time)

```bash
mkdir -p ~/Code/live-transcribe && cd ~/Code/live-transcribe
uv venv --python 3.12 --seed
source .venv/bin/activate
uv pip install faster-whisper>=1.2.1 numpy>=2.0 pyyaml>=6.0 nvidia-cublas-cu12 nvidia-cudnn-cu12
ollama pull qwen2.5:7b-instruct-q5_K_M    # for the Q&A assistant
```

## Slash commands wired

- `/lt-start` — runs `scripts/start.sh` in background.
- `/lt-stop` — kills `transcribe.py` + `parec`.
- `/lt-archive [slug]` — runs `scripts/lt_archive.py`.
- `/ask-live "pregunta"` — one-shot Q&A using `scripts/assistant.py` + transcript live.

## Key environment variables

| Variable | Default | Purpose |
|---|---|---|
| `LT_RUNTIME_DIR` | `~/Code/live-transcribe` | Where venv + models live. |
| `LT_TRANSCRIPT_PATH` | `/tmp/live-transcript.txt` | Live transcript file. |
| `LT_VAULT_DIR` | `~/Documents/live-transcribe-vault` | Obsidian vault root for archives. |
| `LT_PROMPT_FILE` | `scripts/prompts/generic.md` | Assistant system prompt path. |
| `LT_LANGUAGE` | `es` | Whisper language code. |
| `LT_OLLAMA_MODEL` | `qwen2.5:7b-instruct-q5_K_M` | Ollama model id. |
| `LT_BILATERAL` | unset (`0`) | Set to `1` for bilateral capture (mic + remote audio mixed via combined null-sink). See `README.md`. |

## Audio capture flows

Three flows are documented in `README.md`:

- **Flow 1 (Teams native recording)**: best quality, bilateral by
  construction, legally clean consent flow. Recommended for formal
  meetings (<Client> / ⟦ org_name ⟧ / regulated work).
- **Flow 2 (`LT_BILATERAL=1`)**: live bilateral capture via PipeWire
  combined sink. Best for real-time Q&A during meetings where Teams
  recording is unavailable.
- **Flow 0 (default)**: monitor-only capture. Asymmetric — only
  captures what's playing through speakers/headphones, not mic. Kept
  as fallback for one-direction audio (webinars, recorded playback).

## Privacy posture

All audio, transcripts, embeddings, and LLM inferences stay on the host. Custom prompts under `scripts/prompts/*.md` (other than `generic.md` and `example-*.md`) are gitignored to keep meeting-specific context out of source control.

## Hardware target

NVIDIA ⟦ gpu ⟧ Generation Laptop (your VRAM, ). VRAM headroom is tight: Whisper (~1.2 GB) + Qwen 7B q5 (~5 GB) ≈ 6.2 GB. Heavy concurrent loads may evict one of the two.

## Known limitations (deferred to issues)

- Sink capture is bound at startup. Switching audio device mid-meeting requires `/lt-stop` + `/lt-start`.
- `reader_thread` blocked on `stdin.read()` does not wake on SIGTERM until parec closes the pipe.
- No tests yet; coverage 0%.
