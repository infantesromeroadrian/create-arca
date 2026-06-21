"""Live transcription worker.

Reads raw s16le mono PCM from stdin (fed by `parec`), buffers it in fixed-size
chunks, runs faster-whisper on CUDA, and appends timestamped lines to the
transcript file.

Pipeline contract (defined in start.sh):
    parec -d <sink>.monitor --format=s16le --rate=16000 --channels=1 --raw \
        | python transcribe.py
"""
from __future__ import annotations

import logging
import queue
import select
import signal
import sys
import threading
import time
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path

import numpy as np
from faster_whisper import WhisperModel

import config

logger = logging.getLogger(__name__)


@dataclass(slots=True)
class TranscriberStats:
    """Operational counters surfaced on shutdown for ops visibility."""

    chunks_processed: int = 0
    chunks_dropped: int = 0
    transcribe_runtime_errors: int = 0
    transcribe_input_errors: int = 0


@dataclass(slots=True)
class TranscriberWorker:
    """Owns the audio queue, stop event, and worker threads.

    Two threads cooperate:
      - reader_thread: blocks on stdin, slices into CHUNK_BYTES blocks,
        and pushes them into the queue (drop-newest under back-pressure
        so the oldest meeting context is preserved).
      - transcribe_thread: drains the queue, runs Whisper, appends one
        timestamped line per non-empty result.
    """

    model: WhisperModel
    transcript_path: Path
    queue_size: int = config.AUDIO_QUEUE_MAX_CHUNKS
    audio_queue: queue.Queue[bytes] = field(init=False)
    stop_event: threading.Event = field(default_factory=threading.Event)
    stats: TranscriberStats = field(default_factory=TranscriberStats)

    def __post_init__(self) -> None:
        self.audio_queue = queue.Queue(maxsize=self.queue_size)

    # ------------------------------------------------------------------ reader
    def reader_loop(self) -> None:
        """Read raw PCM from stdin and slice into CHUNK_BYTES blocks.

        REQUIRES the stdin contract defined in the module docstring:
        s16le, 16 kHz, mono. Feeding anything else (WAV with header,
        encoded audio) produces silent garbage transcriptions.

        Uses select() with a short timeout instead of a blocking
        read(): if parec stops emitting (sink disconnected, process
        suspended), the thread still wakes up regularly to honour
        stop_event, so SIGTERM shuts the worker down cleanly.
        """
        pending = bytearray()
        stream = sys.stdin.buffer
        fileno = stream.fileno()
        while not self.stop_event.is_set():
            ready, _, _ = select.select([fileno], [], [], config.READER_SELECT_TIMEOUT_S)
            if not ready:
                continue
            data = stream.read(config.READ_BLOCK_BYTES)
            if data is None:
                # Non-blocking read returned no data despite select; loop.
                continue
            if not data:
                # EOF: parec closed the pipe. Signal shutdown to the rest
                # of the worker so transcribe_loop drains and exits.
                logger.info("stdin EOF; signalling stop")
                self.stop_event.set()
                return
            pending.extend(data)
            while len(pending) >= config.CHUNK_BYTES:
                chunk = bytes(pending[: config.CHUNK_BYTES])
                del pending[: config.CHUNK_BYTES]
                try:
                    self.audio_queue.put(chunk, timeout=config.QUEUE_PUT_TIMEOUT_S)
                except queue.Full:
                    # Drop-newest: preserve the oldest meeting context, which
                    # tends to contain the framing commitments. Whisper lag
                    # is transient; older audio is irreplaceable.
                    self.stats.chunks_dropped += 1
                    logger.warning(
                        "dropped audio chunk (queue full); total dropped=%d",
                        self.stats.chunks_dropped,
                    )

    # -------------------------------------------------------------- transcribe
    def transcribe_loop(self) -> None:
        """Drain the queue, run Whisper on each chunk, append to file.

        Append-mode preserves any prior transcript so `lt-restart`
        (documented operation) does not destroy data.
        """
        existed = self.transcript_path.exists() and self.transcript_path.stat().st_size > 0
        mode = "a" if existed else "w"
        with self.transcript_path.open(mode, encoding="utf-8") as transcript_fh:
            header = (
                f"# Resumed {datetime.now().isoformat(timespec='seconds')}\n"
                if existed
                else f"# Live transcript started "
                f"{datetime.now().isoformat(timespec='seconds')}\n"
            )
            transcript_fh.write(header)
            transcript_fh.flush()

            while not self.stop_event.is_set():
                try:
                    raw = self.audio_queue.get(timeout=config.QUEUE_GET_TIMEOUT_S)
                except queue.Empty:
                    continue

                audio = (
                    np.frombuffer(raw, dtype=np.int16).astype(np.float32)
                    / config.INT16_TO_FLOAT_DIVISOR
                )
                if np.abs(audio).max() < config.SILENCE_AMPLITUDE_THRESHOLD:
                    continue  # voice activity gate: skip silent chunks.

                line = self._transcribe_chunk(audio)
                if line:
                    transcript_fh.write(line)
                    transcript_fh.flush()  # keep `tail -f` instantaneous
                    sys.stderr.write(line)
                    sys.stderr.flush()
                self.stats.chunks_processed += 1

    def _transcribe_chunk(self, audio: np.ndarray) -> str:
        timestamp = datetime.now().strftime("%H:%M:%S")
        try:
            segments, _ = self.model.transcribe(
                audio,
                language=config.WHISPER_LANGUAGE,
                vad_filter=True,
                beam_size=config.WHISPER_BEAM_SIZE,
                condition_on_previous_text=False,
            )
            text = " ".join(segment.text.strip() for segment in segments).strip()
        except RuntimeError as exc:
            # CUDA OOM, model crashes, CTranslate2 internal errors. Logged but
            # not fatal — the loop must keep running so the user can recover.
            self.stats.transcribe_runtime_errors += 1
            logger.exception("whisper runtime error")
            return f"[{timestamp}] <TRANSCRIBE_RUNTIME_ERROR: {exc}>\n"
        except ValueError as exc:
            # Bad input shape / dtype mismatch. Indicates a bug upstream.
            self.stats.transcribe_input_errors += 1
            logger.exception("whisper input error")
            return f"[{timestamp}] <TRANSCRIBE_INPUT_ERROR: {exc}>\n"
        # KeyboardInterrupt and MemoryError intentionally bubble up.
        if not text:
            return ""
        return f"[{timestamp}] {text}\n"


def _install_signal_handlers(worker: TranscriberWorker) -> None:
    def _on_signal(_signum: int, _frame: object) -> None:
        worker.stop_event.set()

    signal.signal(signal.SIGINT, _on_signal)
    signal.signal(signal.SIGTERM, _on_signal)


def main() -> None:
    logging.basicConfig(
        level="INFO",
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
        stream=sys.stderr,
    )
    sys.stderr.write("Loading faster-whisper model on CUDA...\n")
    sys.stderr.flush()
    model = WhisperModel(
        config.WHISPER_MODEL,
        device=config.WHISPER_DEVICE,
        compute_type=config.WHISPER_COMPUTE_TYPE,
        download_root=str(config.MODELS_DIR),
    )
    sys.stderr.write(f"Model loaded. Writing transcript to {config.TRANSCRIPT_PATH}\n")
    sys.stderr.flush()

    worker = TranscriberWorker(model=model, transcript_path=config.TRANSCRIPT_PATH)
    _install_signal_handlers(worker)

    threads = [
        threading.Thread(target=worker.reader_loop, daemon=True, name="reader"),
        threading.Thread(target=worker.transcribe_loop, daemon=True, name="whisper"),
    ]
    for thread in threads:
        thread.start()

    while not worker.stop_event.is_set():
        time.sleep(0.5)

    sys.stderr.write(
        f"Shutting down. Stats: processed={worker.stats.chunks_processed} "
        f"dropped={worker.stats.chunks_dropped} "
        f"runtime_errors={worker.stats.transcribe_runtime_errors} "
        f"input_errors={worker.stats.transcribe_input_errors}\n"
    )


if __name__ == "__main__":
    main()
