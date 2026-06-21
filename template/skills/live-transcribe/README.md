# live-transcribe — capture flow recommendations

Three audio-capture flows are supported, ranked by quality.

## Flow 1 — MS Teams native recording (RECOMMENDED for formal meetings)

Best quality. Bilateral audio, native codec, no Linux audio routing
quirks. Use when:

- The meeting is on Microsoft Teams.
- Consent flow is acceptable (Teams shows a recording banner to all
  participants — legally clean for <Client> / ⟦ org_name ⟧ / regulated work).
- Real-time Q&A during the meeting is NOT required.

### Step-by-step

1. **During the meeting** — meeting organiser clicks "Start recording"
   in Teams. Banner appears for all attendees automatically.
2. **After the meeting** — Teams uploads the `.mp4` to SharePoint /
   OneDrive / Stream within ~10-30 minutes.
3. **Download the .mp4** to a local working directory.
4. **Extract audio + transcribe offline** with the runtime venv:

```bash
cd ~/Code/live-transcribe
ffmpeg -i /path/to/reunion.mp4 -ac 1 -ar 16000 -vn audio.wav

source .venv/bin/activate
python - <<'PY'
from faster_whisper import WhisperModel
m = WhisperModel("large-v3-turbo", device="cuda", compute_type="float16")
segs, _ = m.transcribe("audio.wav", language="es", vad_filter=True)
with open("transcript.txt", "w") as f:
    for s in segs:
        f.write(f"[{s.start:7.2f}-{s.end:7.2f}] {s.text}\n")
PY
```

5. **Optional: ask Qwen** about the offline transcript:

```bash
LT_TRANSCRIPT_PATH=/path/to/transcript.txt \
  bash skills/live-transcribe/scripts/ask.sh --prompt prompts/hybrid.md
```

### Why this is the best flow

- Native audio quality (no bluez compression, no asymmetric capture).
- Bilateral by construction — Teams records the meeting mix.
- Legally clean (consent banner is part of Teams UX).
- Resilient — if your laptop crashes mid-meeting, Teams has the cloud copy.

## Flow 2 — Live bilateral (mic + remote audio mixed)

Best for **real-time Q&A during a meeting** when Teams recording is
not available (Zoom without recording, Google Meet, ad-hoc calls).

Captures BOTH directions by combining the local mic + the default sink
monitor into a single null-sink via PipeWire / PulseAudio modules.

### Usage

```bash
LT_BILATERAL=1 bash skills/live-transcribe/scripts/start.sh
```

`start.sh` will:

1. Load `module-null-sink sink_name=lt_combined`.
2. Loopback the default mic source → `lt_combined`.
3. Loopback the default sink monitor → `lt_combined`.
4. Capture `lt_combined.monitor` with `parec` and stream to
   `transcribe.py`.
5. On Ctrl+C / EXIT, unload all 3 modules so nothing leaks.

### Caveats

- **Echo**: the default mic may pick up the remote audio coming out of
  the laptop speakers if you don't wear headphones. If you wear bluez
  headphones, the speakers stay quiet and there's no echo loop.
- **Latency**: 100ms loopback latency is added on each leg. Acceptable
  for transcription, noticeable for round-trip Q&A.
- **Quality**: still degraded vs Flow 1 (bluez compression on the
  remote side). But bilateral, which Flow 0 (current default) is not.
- **Privacy**: this captures EVERYTHING from the mic and EVERYTHING
  going to your speakers/headphones. If you take a personal call mid-
  session, it lands in the transcript. Stop the pipeline if needed.

## Flow 0 — Default monitor (CURRENT, asymmetric)

Captures only the default sink monitor (what's playing through your
speakers/headphones). No mic. This is the original behaviour.

```bash
bash skills/live-transcribe/scripts/start.sh
```

Use only when:

- You only care about what the OTHER side says (e.g. you're listening
  to a recorded webinar / podcast / video and want a transcript).
- You're not in an interactive meeting.

This was the default before 2026-05-06. Kept as fallback because for
single-direction audio (webinars, recorded calls played back) it's
marginally simpler.

## Decision matrix

| Scenario | Use |
|---|---|
| Formal meeting on Teams (<Client> / ⟦ org_name ⟧ / clients) | Flow 1 |
| Live Q&A during any meeting | Flow 2 |
| Listening to recorded webinar / podcast | Flow 0 |
| Standalone monologue dictation | mic-only sink, not this skill |

## Environment variable summary

| Variable | Default | Purpose |
|---|---|---|
| `LT_RUNTIME_DIR` | `~/Code/live-transcribe` | Where venv + models live |
| `LT_TRANSCRIPT_PATH` | `/tmp/live-transcript.txt` | Live transcript file |
| `LT_BILATERAL` | unset (= `0`) | Set to `1` to enable Flow 2 |
| `LT_PROMPT_FILE` | `prompts/generic.md` | System prompt for `ask.sh` |
| `LT_OLLAMA_MODEL` | `qwen2.5:7b-instruct-q5_K_M` | Local LLM for Q&A |
| `LT_WHISPER_MODEL` | `large-v3-turbo` | Whisper transcription model |

## Stop / archive

- `bash skills/live-transcribe/scripts/start.sh` — stop with Ctrl+C
  (the EXIT trap unloads bilateral modules cleanly).
- `/lt-stop` — slash command equivalent (kills transcribe.py + parec).
- `/lt-archive` — copy transcript to Obsidian + summary to Engram.
