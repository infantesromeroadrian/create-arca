"""Shared pytest fixtures and import shim."""
from __future__ import annotations

import sys
from pathlib import Path

import pytest

SCRIPTS_DIR = Path(__file__).resolve().parent.parent / "scripts"
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))


@pytest.fixture
def tmp_transcript(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Path:
    import config

    target = tmp_path / "live-transcript.txt"
    monkeypatch.setattr(config, "TRANSCRIPT_PATH", target)
    return target


@pytest.fixture
def tmp_archive_dir(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Path:
    import config

    target = tmp_path / "archive"
    target.mkdir()
    monkeypatch.setattr(config, "ARCHIVE_DIR", target)
    return target
