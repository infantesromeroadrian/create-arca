"""Centralized configuration for live-transcribe ARCA Layer 2 skill.

Single source of truth for paths, audio capture parameters, model
identifiers, timeouts, and tuning constants. All values can be
overridden via environment variables — see README for the full table.
"""
from __future__ import annotations

import os
from pathlib import Path
from typing import Final

# --------------------------------------------------------------------- paths
TRANSCRIPT_PATH: Final[Path] = Path(
    os.environ.get("LT_TRANSCRIPT_PATH", "/tmp/live-transcript.txt")
)
VAULT_DIR: Final[Path] = Path(
    os.environ.get("LT_VAULT_DIR", str(Path.home() / "Documents" / "live-transcribe-vault"))
)
ARCHIVE_DIR: Final[Path] = VAULT_DIR / "Transcripciones-Reuniones"

# Heavy binaries (Python venv + Whisper models) live in a runtime dir outside
# this skill folder so the skill stays small and version-controllable inside
# .claude. Override via LT_RUNTIME_DIR if your install lives elsewhere.
RUNTIME_DIR: Final[Path] = Path(
    os.environ.get("LT_RUNTIME_DIR", str(Path.home() / "Code" / "live-transcribe"))
)
MODELS_DIR: Final[Path] = RUNTIME_DIR / "models"
PROMPTS_DIR: Final[Path] = Path(__file__).parent / "prompts"
DEFAULT_PROMPT_FILE: Final[Path] = PROMPTS_DIR / "generic.md"

# ------------------------------------------------------------- audio capture
# Must match `parec` invocation in start.sh.
SAMPLE_RATE_HZ: Final[int] = 16_000
BYTES_PER_SAMPLE: Final[int] = 2  # s16le
CHUNK_SECONDS: Final[int] = 8
CHUNK_BYTES: Final[int] = CHUNK_SECONDS * SAMPLE_RATE_HZ * BYTES_PER_SAMPLE
READ_BLOCK_BYTES: Final[int] = 4096

# 200 chunks * 8s = ~26 min of buffered audio if Whisper stalls.
# At 256 KB/chunk that is ~50 MB of host RAM, well within budget.
AUDIO_QUEUE_MAX_CHUNKS: Final[int] = 200

# --------------------------------------------------------- voice activity gate
# Below this max-amplitude threshold (post-normalisation to [-1, 1]) the
# chunk is considered silence and we skip the Whisper call to save GPU.
SILENCE_AMPLITUDE_THRESHOLD: Final[float] = 0.005
INT16_TO_FLOAT_DIVISOR: Final[float] = 32_768.0  # = 2**15

# -------------------------------------------------------------------- whisper
WHISPER_MODEL: Final[str] = os.environ.get("LT_WHISPER_MODEL", "large-v3-turbo")
WHISPER_LANGUAGE: Final[str] = os.environ.get("LT_LANGUAGE", "es")
WHISPER_DEVICE: Final[str] = "cuda"
WHISPER_COMPUTE_TYPE: Final[str] = "int8_float16"
WHISPER_BEAM_SIZE: Final[int] = 1

# --------------------------------------------------------------------- ollama
OLLAMA_URL: Final[str] = os.environ.get(
    "LT_OLLAMA_URL", "http://127.0.0.1:11434/api/chat"
)
OLLAMA_MODEL: Final[str] = os.environ.get(
    "LT_OLLAMA_MODEL", "qwen2.5:7b-instruct-q5_K_M"
)
OLLAMA_TIMEOUT_CHAT_S: Final[float] = 60.0
OLLAMA_TIMEOUT_SUMMARY_S: Final[float] = 90.0
OLLAMA_TEMPERATURE: Final[float] = 0.2

# ------------------------------------------------------------------ assistant
TRANSCRIPT_TAIL_CHARS: Final[int] = 12_000  # ~3000 tokens, well under 32k ctx
HISTORY_TURNS_KEPT: Final[int] = 5
TAIL_PREVIEW_LINES: Final[int] = 30

# --------------------------------------------------------------------- engram
ENGRAM_TIMEOUT_S: Final[float] = 20.0

# ------------------------------------------------------------ misc thresholds
READER_IDLE_SLEEP_S: Final[float] = 0.05
# Short timeout on the reader's select() so the loop wakes up regularly to
# check stop_event even when parec is silent (sink suspended, BT disconnect).
READER_SELECT_TIMEOUT_S: Final[float] = 0.5
QUEUE_PUT_TIMEOUT_S: Final[float] = 0.5
QUEUE_GET_TIMEOUT_S: Final[float] = 0.5
SLUG_MAX_CHARS: Final[int] = 60
