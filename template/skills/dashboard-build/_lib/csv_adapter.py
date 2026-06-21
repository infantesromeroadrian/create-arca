"""CSV adapter for /dashboard-build (ADR-051).

Reads <project>/todos.csv and emits the same intermediate JSON envelope as
parser-core.py does for backlog.md ADR-040 sources. The output contract
(schema.json v1.0.0) is unchanged — only the input parsing differs.

Column mapping (todos.csv → JSON):
  id           → cards[].id  (kept verbatim; TODO-NNN format, not BL-NNN)
  description  → cards[].title
  status       → cards[].status  (open→Backlog, in-progress→InProgress,
                                   done→Done, blocked→Blocked, cancelled→skip)
  priority     → cards[].moscow  (P0/P1→Must, P2→Should, P3→Could, —→Could)
  owner        → cards[].owner
  notes        → cards[].description
  blocker      → added to cards[].description when non-empty

Fields without a source (RICE, cycle, story_points, won_reason) default to
null or empty arrays.  The schema's strict BL-NNN ID pattern is NOT enforced
for CSV sources — caller must pass skip_strict_id=True.
"""

from __future__ import annotations

import csv
import html
import json
import logging
import re
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

logger = logging.getLogger("dashboard-build.csv_adapter")

# Minimum required CSV columns (case-insensitive match after strip).
_REQUIRED_COLS = {"id", "description", "status"}

# Exit codes per ADR-051 E5xx extension to parser-contract.md.
E501_UNRECOGNISED_FORMAT = 50  # source file not CSV / not recognised
E502_CSV_MISSING_COLS = 51     # required columns absent
E503_CSV_ENCODING = 52         # CSV encoding error


def _map_status(raw: str) -> str | None:
    """Map todos.csv status values to dashboard board columns.

    Returns None for statuses that should be skipped (cancelled, etc.).
    """
    raw = raw.strip().lower()
    mapping = {
        "open": "Backlog",
        "backlog": "Backlog",
        "in-progress": "InProgress",
        "in_progress": "InProgress",
        "inprogress": "InProgress",
        "done": "Done",
        "closed": "Done",
        "blocked": "Blocked",
        "blocking": "Blocked",
    }
    return mapping.get(raw)  # None for cancelled, unknown, empty


def _map_moscow(priority: str) -> str:
    """Map P0/P1/P2/P3 priority tiers to MoSCoW labels."""
    p = priority.strip().upper()
    if p in ("P0", "P1"):
        return "Must"
    if p == "P2":
        return "Should"
    return "Could"  # P3, empty, or anything else


def _null_rice() -> dict[str, Any]:
    return {"reach": None, "impact": None, "confidence": None, "effort": None, "score": None}


def parse_csv(
    csv_path: Path,
    project_root: Path,
    schema_version: str = "1.0.0",
) -> dict[str, Any]:
    """Parse todos.csv and return the JSON envelope dict.

    Raises SystemExit with E5xx code on fatal errors.
    stdout is NOT written here — caller handles serialisation.
    """
    # Encoding check.
    try:
        raw = csv_path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        logger.error("E503 CSV encoding error: %s is not valid UTF-8", csv_path)
        sys.exit(E503_CSV_ENCODING)
    except OSError as exc:
        logger.error("E503 cannot read CSV: %s — %s", csv_path, exc)
        sys.exit(E503_CSV_ENCODING)

    reader = csv.DictReader(raw.splitlines())
    if reader.fieldnames is None:
        logger.error("E502 CSV has no header row: %s", csv_path)
        sys.exit(E502_CSV_MISSING_COLS)

    cols = {c.strip().lower() for c in reader.fieldnames}
    missing = _REQUIRED_COLS - cols
    if missing:
        logger.error("E502 CSV missing required columns %s in %s", sorted(missing), csv_path)
        sys.exit(E502_CSV_MISSING_COLS)

    cards: list[dict[str, Any]] = []
    warnings: list[dict[str, Any]] = []

    for row in reader:
        card_id = (row.get("id") or "").strip()
        raw_status = (row.get("status") or "").strip()
        title = (row.get("description") or "").strip()

        if not card_id or not title:
            continue  # skip empty rows silently

        status = _map_status(raw_status)
        if status is None:
            # cancelled / unknown — skip from board (treated as WONT-equivalent)
            logger.debug("skipping card %s with status %r", card_id, raw_status)
            continue

        priority = (row.get("priority") or "").strip()
        moscow = _map_moscow(priority)
        owner = (row.get("owner") or "").strip() or None

        # Combine notes + blocker into description field.
        notes = (row.get("notes") or "").strip()
        blocker = (row.get("blocker") or "").strip()
        desc_parts = [p for p in [notes, f"Blocker: {blocker}" if blocker else ""] if p]
        description = " | ".join(desc_parts) or None

        # internal_project acts as a rough cycle approximation when present.
        # We cannot derive a canonical C1..C14 cycle from CSV, so emit null.
        cycle: str | None = None

        cards.append({
            "id": card_id,
            "title": html.escape(title, quote=True),
            "status": status,
            "moscow": moscow,
            "type": None,
            "cycle": cycle,
            "story_points": None,
            "rice": _null_rice(),
            "dependencies": [],
            "owner": html.escape(owner, quote=True) if owner else None,
            "description": html.escape(description, quote=True) if description else None,
            # won_reason omitted for non-WONT cards per ADR-049 B4 decision.
        })

    if not cards:
        warnings.append({
            "code": "W501",
            "message": "todos.csv produced zero visible cards (all rows cancelled or empty)",
            "path": str(csv_path.relative_to(project_root)),
        })
        logger.warning("W501 zero cards parsed from %s", csv_path)

    envelope = {
        "schema_version": schema_version,
        "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "source": {
            "backlog_path": str(csv_path.relative_to(project_root)),
            "project_root": str(project_root),
            "adapter": "csv_adapter",  # marks non-canonical source
            "sidecars": [],
        },
        "project_meta": {
            "name": project_root.name,
            "objectives": [],
            "stakeholders": [],
            "ml_problem_statement": "",
            "success_metrics": [],
        },
        "cards": cards,
        "reviews": [],
        "warnings": warnings,
    }

    logger.info("csv_adapter: parsed %d visible cards from %s", len(cards), csv_path.name)
    return envelope
