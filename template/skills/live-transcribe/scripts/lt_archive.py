"""End-of-meeting archiver.

Reads the live transcript and:
  1. Saves the full transcript with YAML frontmatter to
     <vault>/Transcripciones-Reuniones/<YYYY-MM-DD>-<slug>.md.
  2. Generates a 5-7 bullet executive summary via local Ollama.
  3. Persists the summary to Engram via the `engram` CLI.
  4. Optionally deletes the live transcript file.

Atomicity rules (enforced):
  - If the live transcribe process is still running, refuse to delete
    the transcript (avoids reading a half-written file).
  - If Ollama or Engram fail, the transcript is preserved so the user
    can retry without data loss.

Usage:
    python lt_archive.py [--slug SLUG] [--project NAME] [--attendees A,B] [--keep]
                         [--no-engram] [--prompt path.md]
"""
from __future__ import annotations

import argparse
import logging
import shutil
import subprocess
import sys
import unicodedata
from dataclasses import dataclass
from datetime import date
from pathlib import Path
from typing import Final

import yaml

import config
from ollama_client import (
    OllamaError,
    OllamaMessage,
    OllamaUnreachableError,
    query_chat,
)

logger = logging.getLogger(__name__)

DEFAULT_SUMMARY_PROMPT: Final[str] = (
    "Eres analista de reuniones. Recibes una transcripción cruda "
    "en castellano de una reunión profesional.\n"
    "\n"
    "Genera un resumen ejecutivo en 5-7 bullets, EN CASTELLANO, capturando:\n"
    "- Decisiones acordadas (con quién y qué).\n"
    "- Pendientes (qué tarea, quién la ejecuta, deadline si se mencionó).\n"
    "- Riesgos o señales de alarma (compromisos ambiguos, puntos sin cerrar).\n"
    "- Términos críticos textuales si aplican "
    "(modalidad, contrato, fechas, dietas).\n"
    "\n"
    "Devuelve SOLO los bullets, sin preámbulo ni cierre. "
    "Cada bullet empieza con `- `.\n"
)


@dataclass(frozen=True, slots=True)
class ArchiveArgs:
    slug: str
    project: str
    attendees: list[str]
    keep_transcript: bool
    skip_engram: bool
    prompt_text: str


def slugify(text: str) -> str:
    """Lowercase, ASCII-fold accents, dash-join, cap to SLUG_MAX_CHARS."""
    text = unicodedata.normalize("NFKD", text)
    text = text.encode("ascii", "ignore").decode("ascii").lower().strip()
    cleaned = []
    for char in text:
        if char.isalnum():
            cleaned.append(char)
        elif char in {" ", "-", "_"}:
            cleaned.append("-")
    out = "".join(cleaned)
    while "--" in out:
        out = out.replace("--", "-")
    return out[: config.SLUG_MAX_CHARS].strip("-") or "reunion"


def transcribe_running() -> bool:
    """True if a transcribe.py process is currently writing the transcript."""
    result = subprocess.run(
        ["pgrep", "-f", "transcribe.py"],
        capture_output=True,
        text=True,
        check=False,
    )
    return result.returncode == 0


def read_transcript() -> str:
    if not config.TRANSCRIPT_PATH.exists():
        sys.exit(
            f"No existe {config.TRANSCRIPT_PATH}. ¿Has arrancado la "
            f"transcripción con `lt`?"
        )
    text = config.TRANSCRIPT_PATH.read_text(encoding="utf-8", errors="replace").strip()
    if not text:
        sys.exit("El transcript está vacío.")
    return text


def query_summary(transcript: str, prompt_text: str) -> str:
    messages: list[OllamaMessage] = [
        {"role": "system", "content": prompt_text},
        {"role": "user", "content": transcript},
    ]
    return query_chat(messages, timeout=config.OLLAMA_TIMEOUT_SUMMARY_S)


def write_obsidian_note(
    transcript: str,
    args: ArchiveArgs,
    summary: str,
) -> Path:
    config.ARCHIVE_DIR.mkdir(parents=True, exist_ok=True)
    today = date.today().isoformat()
    target = config.ARCHIVE_DIR / f"{today}-{args.slug}.md"
    counter = 2
    while target.exists():
        target = config.ARCHIVE_DIR / f"{today}-{args.slug}-{counter}.md"
        counter += 1

    frontmatter = yaml.safe_dump(
        {
            "date": today,
            "type": "meeting-transcript",
            "project": args.project,
            "attendees": args.attendees,
            "slug": args.slug,
        },
        sort_keys=False,
        allow_unicode=True,
        default_flow_style=False,
    )
    body = (
        f"---\n{frontmatter}---\n\n"
        f"# Resumen ejecutivo\n\n{summary}\n\n"
        f"# Transcripción completa\n\n```\n{transcript}\n```\n"
    )
    target.write_text(body, encoding="utf-8")
    return target


def save_to_engram(args: ArchiveArgs, summary: str, obsidian_path: Path) -> str:
    """Return engram CLI stdout (or an error string starting with `[engram-error`)."""
    if shutil.which("engram") is None:
        return "[engram-error: `engram` CLI not found in PATH]"
    title = f"meeting-{date.today().isoformat()}-{args.slug}"
    body = (
        f"Resumen reunión {args.project} ({date.today().isoformat()}).\n\n"
        f"{summary}\n\n"
        f"Transcripción completa: {obsidian_path}"
    )
    cmd = [
        "engram", "save", title, body,
        "--type", "meeting-summary",
        "--project", args.project,
    ]
    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=config.ENGRAM_TIMEOUT_S,
            check=True,
        )
    except subprocess.TimeoutExpired:
        return f"[engram-error: timeout after {config.ENGRAM_TIMEOUT_S}s]"
    except subprocess.CalledProcessError as exc:
        return f"[engram-error: {exc.stderr.strip() or exc}]"
    return (result.stdout or "saved").strip()


def _prompt_or_die(value: str | None, prompt: str, flag: str) -> str:
    if value:
        return value
    if not sys.stdin.isatty():
        sys.exit(f"Modo no-interactivo: usa {flag} en CLI.")
    return input(prompt).strip()


def _load_summary_prompt(path_arg: str | None) -> str:
    if not path_arg:
        return DEFAULT_SUMMARY_PROMPT
    path = Path(path_arg).expanduser()
    if not path.exists():
        sys.exit(f"Prompt file not found: {path}")
    return path.read_text(encoding="utf-8").strip()


def collect_args() -> ArchiveArgs:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--slug", help="Slug for the meeting (e.g. onboarding-rrhh).")
    parser.add_argument("--project", default="default", help="Project tag.")
    parser.add_argument("--attendees", default="", help="CSV list of attendees.")
    parser.add_argument(
        "--keep",
        action="store_true",
        help="Preserve the live transcript file after archiving.",
    )
    parser.add_argument(
        "--no-engram",
        action="store_true",
        help="Skip Engram persistence; only write the Obsidian note.",
    )
    parser.add_argument(
        "--prompt",
        help="Path to a custom summary prompt file (default: built-in).",
    )
    parsed = parser.parse_args()

    slug_raw = _prompt_or_die(
        parsed.slug,
        "Slug de la reunión (ej: onboarding-rrhh): ",
        "--slug",
    )
    if not slug_raw.strip():
        sys.exit("Slug vacío, abortando.")
    attendees_str = parsed.attendees or (
        input("Asistentes (CSV, vacío para omitir): ").strip()
        if sys.stdin.isatty()
        else ""
    )
    attendees = [a.strip() for a in attendees_str.split(",") if a.strip()]

    return ArchiveArgs(
        slug=slugify(slug_raw),
        project=parsed.project,
        attendees=attendees,
        keep_transcript=parsed.keep,
        skip_engram=parsed.no_engram,
        prompt_text=_load_summary_prompt(parsed.prompt),
    )


def main() -> None:
    logging.basicConfig(
        level="INFO",
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
    )

    if transcribe_running():
        sys.exit(
            "transcribe.py sigue corriendo. Para con `lt-stop` antes de "
            "archivar (sino el transcript puede leerse incompleto)."
        )

    transcript = read_transcript()
    print(
        f"Transcript leído: {len(transcript)} caracteres, "
        f"{transcript.count(chr(10))} líneas"
    )

    args = collect_args()

    print(f"\nGenerando resumen con Ollama {config.OLLAMA_MODEL}...")
    try:
        summary = query_summary(transcript, args.prompt_text)
    except OllamaUnreachableError as exc:
        sys.exit(f"Ollama no disponible: {exc}. Reintenta cuando arranque.")
    except OllamaError as exc:
        sys.exit(f"Error generando resumen: {exc}")
    print(f"Resumen ({len(summary)} chars):\n{summary}\n")

    obsidian_path = write_obsidian_note(transcript, args, summary)
    print(f"Obsidian: {obsidian_path}")

    if args.skip_engram:
        engram_status = "[skipped via --no-engram]"
    else:
        engram_status = save_to_engram(args, summary, obsidian_path)
    print(f"Engram: {engram_status}")

    engram_failed = engram_status.startswith("[engram-error")
    if engram_failed and not args.skip_engram:
        sys.exit(
            "Engram falló. Transcript preservado para reintento; "
            "el note Obsidian ya está escrito."
        )

    if not args.keep_transcript:
        config.TRANSCRIPT_PATH.unlink(missing_ok=True)
        print(f"Borrado {config.TRANSCRIPT_PATH} (use --keep para preservar)")


if __name__ == "__main__":
    main()
