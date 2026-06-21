"""Minimal Ollama HTTP client shared by assistant.py and lt_archive.py.

Wraps the local `/api/chat` endpoint with structured error types so callers
can degrade gracefully instead of crashing mid-pipeline.
"""
from __future__ import annotations

import json
import logging
import urllib.error
import urllib.request
from typing import Final, Literal, TypedDict

import config  # files run as flat scripts, not as a package

logger = logging.getLogger(__name__)

DEFAULT_OPTIONS: Final[dict[str, float]] = {"temperature": config.OLLAMA_TEMPERATURE}


class OllamaMessage(TypedDict):
    """Chat message shape accepted by Ollama's /api/chat."""

    role: Literal["system", "user", "assistant"]
    content: str


class OllamaError(RuntimeError):
    """Base class for any failure of the local Ollama call."""


class OllamaUnreachableError(OllamaError):
    """Connection refused, DNS failure, or read timeout."""


class OllamaResponseMalformedError(OllamaError):
    """Response was returned but did not match the expected schema."""


def query_chat(
    messages: list[OllamaMessage],
    *,
    model: str = config.OLLAMA_MODEL,
    timeout: float = config.OLLAMA_TIMEOUT_CHAT_S,
    options: dict[str, float] | None = None,
) -> str:
    """Send a chat request to local Ollama and return the assistant content.

    Raises:
        OllamaUnreachableError: server not reachable, refused, or timed out.
        OllamaResponseMalformedError: response JSON missing expected fields.
    """
    payload = {
        "model": model,
        "messages": messages,
        "stream": False,
        "options": options or DEFAULT_OPTIONS,
    }
    request = urllib.request.Request(
        config.OLLAMA_URL,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            data = json.loads(response.read().decode("utf-8"))
    except (urllib.error.URLError, TimeoutError, ConnectionError) as exc:
        logger.warning("ollama unreachable at %s: %s", config.OLLAMA_URL, exc)
        raise OllamaUnreachableError(
            f"Cannot reach Ollama at {config.OLLAMA_URL}: {exc}"
        ) from exc
    except json.JSONDecodeError as exc:
        raise OllamaResponseMalformedError("Ollama returned invalid JSON") from exc

    try:
        content = data["message"]["content"]
    except (KeyError, TypeError) as exc:
        raise OllamaResponseMalformedError(
            f"Unexpected response shape: {data!r}"
        ) from exc
    if not isinstance(content, str):
        raise OllamaResponseMalformedError(
            f"`message.content` is not a string: {content!r}"
        )
    return content.strip()
