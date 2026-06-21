---
description: Read ARCA's last full answer out loud via ElevenLabs TTS (manual mode, no summary)
allowed-tools: Bash(~/.claude/hooks/arca-tts.sh:*)
---

# /speak — ARCA out-loud (manual)

Speak ARCA's **entire** last answer aloud through ElevenLabs TTS. Unlike the
automatic Stop hook, manual mode does **not** summarise and ignores the length
threshold — it reads the whole response verbatim (still bounded by the hard
character cap in the config, as a credit guardrail).

The TTS pipeline is fully detached and fail-open: it never blocks this session.
If the key is missing, the network is down, or no audio player is available,
it stays silent and exits cleanly.

## Run

```bash
~/.claude/hooks/arca-tts.sh --speak
```

That single command:
1. Finds the active session transcript (newest `*.jsonl` under `~/.claude/projects`).
2. Extracts the last assistant message and strips markdown/code/URLs for clean speech.
3. Spawns a detached worker that synthesises and plays the audio, then returns immediately.

## Configuration

Voice, model, char cap and players live in `~/.config/elevenlabs/config.sh`.
Change `ELEVENLABS_VOICE_ID` there to switch voices. The API key is read from
`~/.config/elevenlabs/key` (plain text, never hardcoded).
