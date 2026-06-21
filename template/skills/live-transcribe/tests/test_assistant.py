"""Tests for assistant: read_transcript truncation, build_messages structure."""
from __future__ import annotations

from pathlib import Path

import pytest

import assistant  # noqa: E402  (sys.path injected by conftest)
import config


def test_read_transcript_missing_returns_placeholder(tmp_transcript: Path) -> None:
    text, truncated = assistant.read_transcript()
    assert "[Sin transcripción todavía]" in text
    assert truncated is False


def test_read_transcript_short_returns_full(tmp_transcript: Path) -> None:
    tmp_transcript.write_text("[09:00] hola\n", encoding="utf-8")
    text, truncated = assistant.read_transcript()
    assert "hola" in text
    assert truncated is False


def test_read_transcript_long_truncates(
    tmp_transcript: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr(config, "TRANSCRIPT_TAIL_CHARS", 50)
    tmp_transcript.write_text("a" * 200, encoding="utf-8")
    text, truncated = assistant.read_transcript()
    assert truncated is True
    assert len(text) == 50


# ---------------------------------------------------------------- build_messages
def test_build_messages_structure(tmp_transcript: Path) -> None:
    tmp_transcript.write_text("[09:00] X dijo Y", encoding="utf-8")
    msgs = assistant.build_messages(
        question="¿qué dijo X?",
        history=[],
        system_prompt="SYS",
    )
    assert len(msgs) == 2
    assert msgs[0]["role"] == "system"
    assert msgs[0]["content"] == "SYS"
    assert msgs[1]["role"] == "user"
    assert "¿qué dijo X?" in msgs[1]["content"]
    assert "X dijo Y" in msgs[1]["content"]


def test_build_messages_history_interleaved(tmp_transcript: Path) -> None:
    tmp_transcript.write_text("contenido", encoding="utf-8")
    history = [
        assistant.QATurn(question="q1", answer="a1"),
        assistant.QATurn(question="q2", answer="a2"),
    ]
    msgs = assistant.build_messages("q3", history, "SYS")
    # system + 2*(user, assistant) + user
    assert [m["role"] for m in msgs] == [
        "system",
        "user",
        "assistant",
        "user",
        "assistant",
        "user",
    ]
    assert msgs[1]["content"] == "q1"
    assert msgs[2]["content"] == "a1"
    assert msgs[3]["content"] == "q2"
    assert msgs[4]["content"] == "a2"
    assert "q3" in msgs[5]["content"]


def test_build_messages_truncation_note_outside_transcript_block(
    tmp_transcript: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr(config, "TRANSCRIPT_TAIL_CHARS", 30)
    tmp_transcript.write_text("a" * 200, encoding="utf-8")
    msgs = assistant.build_messages("q?", [], "SYS")
    user_block = msgs[-1]["content"]
    note_idx = user_block.find("NOTA SISTEMA")
    transcript_idx = user_block.find("=== TRANSCRIPCIÓN")
    assert note_idx != -1
    assert transcript_idx != -1
    # The system note must appear BEFORE the transcript block so the LLM does
    # not interpret it as someone speaking in the meeting.
    assert note_idx < transcript_idx


# ----------------------------------------------------- prompt path resolution
def test_resolve_prompt_path_cli_arg_wins(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("LT_PROMPT_FILE", "/should/not/win")
    out = assistant._resolve_prompt_path("/cli/path.md")
    assert out == Path("/cli/path.md")


def test_resolve_prompt_path_env_var(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("LT_PROMPT_FILE", "/from/env.md")
    out = assistant._resolve_prompt_path(None)
    assert out == Path("/from/env.md")


def test_resolve_prompt_path_default(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("LT_PROMPT_FILE", raising=False)
    out = assistant._resolve_prompt_path(None)
    assert out == config.DEFAULT_PROMPT_FILE


def test_load_system_prompt_missing_exits(tmp_path: Path) -> None:
    with pytest.raises(SystemExit) as exc:
        assistant.load_system_prompt(tmp_path / "nope.md")
    assert "not found" in str(exc.value)


def test_load_system_prompt_strips_whitespace(tmp_path: Path) -> None:
    prompt_file = tmp_path / "p.md"
    prompt_file.write_text("\n\n  prompt content\n\n", encoding="utf-8")
    assert assistant.load_system_prompt(prompt_file) == "prompt content"
