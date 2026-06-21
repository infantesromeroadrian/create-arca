"""Tests for ollama_client: query_chat happy path + structured errors."""
from __future__ import annotations

import io
import json
import urllib.error
from unittest.mock import patch

import pytest

import ollama_client  # noqa: E402  (sys.path injected by conftest)


class _FakeResponse:
    """Minimal context-manager-compatible response object for urlopen mocks."""

    def __init__(self, payload: dict | bytes) -> None:
        if isinstance(payload, dict):
            payload = json.dumps(payload).encode("utf-8")
        self._buf = io.BytesIO(payload)

    def read(self) -> bytes:
        return self._buf.read()

    def __enter__(self):
        return self

    def __exit__(self, *args: object) -> None:
        return None


def test_query_chat_happy_path() -> None:
    fake = _FakeResponse({"message": {"content": "  hola desde Qwen  "}})
    with patch("urllib.request.urlopen", return_value=fake):
        out = ollama_client.query_chat([{"role": "user", "content": "hi"}])
    assert out == "hola desde Qwen"


def test_query_chat_strips_trailing_whitespace() -> None:
    fake = _FakeResponse({"message": {"content": "x\n"}})
    with patch("urllib.request.urlopen", return_value=fake):
        assert ollama_client.query_chat([{"role": "user", "content": "x"}]) == "x"


def test_query_chat_unreachable_raises_typed_error() -> None:
    with patch(
        "urllib.request.urlopen",
        side_effect=urllib.error.URLError("connection refused"),
    ), pytest.raises(ollama_client.OllamaUnreachableError):
        ollama_client.query_chat([{"role": "user", "content": "x"}])


def test_query_chat_timeout_raises_typed_error() -> None:
    with patch("urllib.request.urlopen", side_effect=TimeoutError("slow")), pytest.raises(
        ollama_client.OllamaUnreachableError
    ):
        ollama_client.query_chat([{"role": "user", "content": "x"}])


def test_query_chat_malformed_json_raises_typed_error() -> None:
    fake = _FakeResponse(b"this is not json")
    with patch(
        "urllib.request.urlopen", return_value=fake
    ), pytest.raises(ollama_client.OllamaResponseMalformedError):
        ollama_client.query_chat([{"role": "user", "content": "x"}])


def test_query_chat_missing_message_field_raises() -> None:
    fake = _FakeResponse({"unexpected": "shape"})
    with patch(
        "urllib.request.urlopen", return_value=fake
    ), pytest.raises(ollama_client.OllamaResponseMalformedError):
        ollama_client.query_chat([{"role": "user", "content": "x"}])


def test_query_chat_non_string_content_raises() -> None:
    fake = _FakeResponse({"message": {"content": ["list", "instead", "of", "str"]}})
    with patch(
        "urllib.request.urlopen", return_value=fake
    ), pytest.raises(ollama_client.OllamaResponseMalformedError):
        ollama_client.query_chat([{"role": "user", "content": "x"}])
