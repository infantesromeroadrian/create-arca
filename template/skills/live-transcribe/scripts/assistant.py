"""Live meeting assistant — interactive Q&A REPL.

Reads the live Whisper transcript on every query and answers via local
Ollama. The system prompt is loaded from an external file (default
`prompts/generic.md`) so domain-specific context stays out of source.

Usage:
    python assistant.py [--prompt path/to/prompt.md]
    LT_PROMPT_FILE=prompts/my-meeting.md python assistant.py
"""
from __future__ import annotations

import argparse
import logging
import os
import sys
import time
from dataclasses import dataclass
from pathlib import Path

import config
from ollama_client import (
    OllamaError,
    OllamaMessage,
    OllamaUnreachableError,
    query_chat,
)

logger = logging.getLogger(__name__)


@dataclass(frozen=True, slots=True)
class QATurn:
    """A single question-answer exchange kept in conversation history."""

    question: str
    answer: str


def _resolve_prompt_path(cli_value: str | None) -> Path:
    """Resolve precedence: --prompt flag > LT_PROMPT_FILE env > default."""
    if cli_value:
        return Path(cli_value).expanduser()
    env_value = os.environ.get("LT_PROMPT_FILE")
    if env_value:
        return Path(env_value).expanduser()
    return config.DEFAULT_PROMPT_FILE


def load_system_prompt(path: Path) -> str:
    if not path.exists():
        sys.exit(f"System prompt file not found: {path}")
    return path.read_text(encoding="utf-8").strip()


def read_transcript() -> tuple[str, bool]:
    """Return (text, truncated_flag). Empty file → placeholder text."""
    if not config.TRANSCRIPT_PATH.exists():
        return "[Sin transcripción todavía]", False
    raw = config.TRANSCRIPT_PATH.read_text(encoding="utf-8", errors="replace")
    if len(raw) <= config.TRANSCRIPT_TAIL_CHARS:
        return raw, False
    return raw[-config.TRANSCRIPT_TAIL_CHARS :], True


def build_messages(
    question: str,
    history: list[QATurn],
    system_prompt: str,
) -> list[OllamaMessage]:
    transcript, truncated = read_transcript()
    truncation_note = (
        "[NOTA SISTEMA: la transcripción mostrada está truncada al inicio "
        "por longitud; solo verás la cola.]\n\n"
        if truncated
        else ""
    )
    user_block = (
        f"{truncation_note}"
        f"=== TRANSCRIPCIÓN EN VIVO DE LA REUNIÓN (lo último al final) ===\n"
        f"{transcript}\n"
        f"=== FIN TRANSCRIPCIÓN ===\n\n"
        f"Pregunta de Adrián: {question}"
    )
    messages: list[OllamaMessage] = [{"role": "system", "content": system_prompt}]
    for turn in history:
        messages.append({"role": "user", "content": turn.question})
        messages.append({"role": "assistant", "content": turn.answer})
    messages.append({"role": "user", "content": user_block})
    return messages


def _print_answer(elapsed_s: float, text: str) -> None:
    print(f"\n┌─ ({elapsed_s:.1f}s) ─────────────────────────────")
    for line in text.splitlines() or [""]:
        print(f"│ {line}")
    print("└──────────────────────────────────────────────")


def _handle_command(command: str, history: list[QATurn]) -> list[QATurn]:
    if command == "/tail":
        text, _ = read_transcript()
        tail = "\n".join(text.splitlines()[-config.TAIL_PREVIEW_LINES :])
        print(f"\n--- transcript (últimas {config.TAIL_PREVIEW_LINES} líneas) ---")
        print(tail)
        print("---")
        return history
    if command == "/clear":
        print("Historial reseteado.")
        return []
    print(f"Comando no reconocido: {command}. Disponibles: /tail, /clear")
    return history


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--prompt",
        help="Path to a markdown file with the system prompt "
        "(default: prompts/generic.md, or env LT_PROMPT_FILE).",
    )
    args = parser.parse_args()

    logging.basicConfig(
        level=os.environ.get("LT_LOG_LEVEL", "WARNING"),
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
    )

    prompt_path = _resolve_prompt_path(args.prompt)
    system_prompt = load_system_prompt(prompt_path)

    print("=" * 70)
    print(f" Live meeting assistant | model: {config.OLLAMA_MODEL}")
    print(f" Prompt: {prompt_path}")
    print(f" Transcript: {config.TRANSCRIPT_PATH}")
    print(" Pregunta + ENTER. Comandos: /tail, /clear. Ctrl+C para salir.")
    print("=" * 70)

    history: list[QATurn] = []
    try:
        while True:
            try:
                question = input("\n> ").strip()
            except EOFError:
                break
            if not question:
                continue
            if question.startswith("/"):
                history = _handle_command(question, history)
                continue

            print("...")
            start = time.time()
            try:
                answer = query_chat(build_messages(question, history, system_prompt))
            except OllamaUnreachableError as exc:
                _print_answer(time.time() - start, f"[Ollama no disponible: {exc}]")
                continue
            except OllamaError as exc:
                _print_answer(time.time() - start, f"[Error Ollama: {exc}]")
                continue

            _print_answer(time.time() - start, answer)
            history.append(QATurn(question=question, answer=answer))
            if len(history) > config.HISTORY_TURNS_KEPT:
                history = history[-config.HISTORY_TURNS_KEPT :]
    except KeyboardInterrupt:
        print("\nSaliendo.")


if __name__ == "__main__":
    main()
