"""Tests for lt_archive."""
from __future__ import annotations

import subprocess
from pathlib import Path
from unittest.mock import patch

import pytest

import lt_archive  # noqa: E402  (sys.path injected by conftest)


@pytest.mark.parametrize(
    "raw,expected",
    [
        ("Reunion Onboarding RRHH", "reunion-onboarding-rrhh"),
        ("  multiple   spaces  ", "multiple-spaces"),
        ("../../etc/passwd", "etcpasswd"),
        ("", "reunion"),
        ("---", "reunion"),
        ("Reunion 4 mayo", "reunion-4-mayo"),
        ("Reunión Onboarding ñ", "reunion-onboarding-n"),
    ],
)
def test_slugify_cases(raw: str, expected: str) -> None:
    assert lt_archive.slugify(raw) == expected


def test_slugify_caps_at_max_chars() -> None:
    out = lt_archive.slugify("a" * 500)
    assert len(out) <= 60


def test_read_transcript_missing_exits(tmp_transcript: Path) -> None:
    with pytest.raises(SystemExit):
        lt_archive.read_transcript()


def test_read_transcript_empty_exits(tmp_transcript: Path) -> None:
    tmp_transcript.write_text("", encoding="utf-8")
    with pytest.raises(SystemExit):
        lt_archive.read_transcript()


def test_read_transcript_returns_content(tmp_transcript: Path) -> None:
    tmp_transcript.write_text("[09:00] hola\n", encoding="utf-8")
    out = lt_archive.read_transcript()
    assert "hola" in out


def _make_args(slug: str = "test-meeting") -> lt_archive.ArchiveArgs:
    return lt_archive.ArchiveArgs(
        slug=slug, project="testproject", attendees=["Alice", "Bob"],
        keep_transcript=False, skip_engram=False, prompt_text="dummy",
    )


def test_write_obsidian_note_creates_file(tmp_archive_dir: Path) -> None:
    args = _make_args()
    target = lt_archive.write_obsidian_note("transcript", args, "- bullet")
    assert target.exists()
    body = target.read_text(encoding="utf-8")
    assert body.startswith("---\n")
    assert "Alice" in body
    assert "transcript" in body


def test_write_obsidian_note_collision_suffix(tmp_archive_dir: Path) -> None:
    args = _make_args()
    first = lt_archive.write_obsidian_note("x", args, "y")
    second = lt_archive.write_obsidian_note("x", args, "y")
    assert first.name != second.name
    assert second.name.endswith("-2.md")


def test_write_obsidian_note_yaml_safe(tmp_archive_dir: Path) -> None:
    import yaml
    args = lt_archive.ArchiveArgs(
        slug="injtest", project="proj",
        attendees=["Alice", "Bob]\nmalicious_field: pwned\n[evil"],
        keep_transcript=False, skip_engram=False, prompt_text="x",
    )
    target = lt_archive.write_obsidian_note("t", args, "s")
    front = target.read_text(encoding="utf-8").split("---\n", 2)[1]
    parsed = yaml.safe_load(front)
    assert "malicious_field" not in parsed
    assert len(parsed["attendees"]) == 2


def test_save_to_engram_cli_missing(tmp_path: Path) -> None:
    with patch("shutil.which", return_value=None):
        result = lt_archive.save_to_engram(_make_args(), "s", tmp_path / "n.md")
    assert result.startswith("[engram-error")


def test_save_to_engram_timeout(tmp_path: Path) -> None:
    with patch("shutil.which", return_value="/usr/bin/engram"), patch(
        "subprocess.run",
        side_effect=subprocess.TimeoutExpired(cmd="engram", timeout=20),
    ):
        result = lt_archive.save_to_engram(_make_args(), "s", tmp_path / "n.md")
    assert "timeout" in result


def test_save_to_engram_success(tmp_path: Path) -> None:
    fake = subprocess.CompletedProcess(args=["engram"], returncode=0,
                                       stdout="obs-123\n", stderr="")
    with patch("shutil.which", return_value="/usr/bin/engram"), patch(
        "subprocess.run", return_value=fake,
    ):
        result = lt_archive.save_to_engram(_make_args(), "s", tmp_path / "n.md")
    assert result == "obs-123"


def test_transcribe_running_no_match() -> None:
    fake = subprocess.CompletedProcess(args=["pgrep"], returncode=1,
                                       stdout="", stderr="")
    with patch("subprocess.run", return_value=fake):
        assert lt_archive.transcribe_running() is False


def test_transcribe_running_match() -> None:
    fake = subprocess.CompletedProcess(args=["pgrep"], returncode=0,
                                       stdout="12345\n", stderr="")
    with patch("subprocess.run", return_value=fake):
        assert lt_archive.transcribe_running() is True
