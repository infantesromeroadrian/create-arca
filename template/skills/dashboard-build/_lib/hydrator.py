"""HTML hydrator for the dashboard template.

Reads ``templates/dashboard/index.html`` plus the parser envelope and emits a
fully-hydrated HTML document. Every interpolated value is HTML-escaped via
``html.escape(value, quote=True)`` -- the template ships inert and trusts the
hydrator to defend against stored XSS in user-authored Unicode (card titles,
ML problem statements, review summaries, stakeholder names, metric labels).

Template placeholder conventions (mirrors the banner in index.html):
  - Scalar:           ``__VAR__`` (double-underscore wrapped, UPPER_SNAKE)
  - Iterable loop:    ``<!-- TEMPLATE:NAME --> body <!-- /TEMPLATE:NAME -->``
  - Conditional empty:``<!-- TEMPLATE:IFEMPTY_NAME --> body <!-- /TEMPLATE:IFEMPTY_NAME -->``
  - Conditional any:  ``<!-- TEMPLATE:IFANY_NAME --> body <!-- /TEMPLATE:IFANY_NAME -->``
"""

from __future__ import annotations

import html
import re
from pathlib import Path
from typing import Any

# Status values rendered as separate columns in the Scrum Board.
_STATUS_COLUMNS: tuple[tuple[str, str], ...] = (
    ("CARDS_BACKLOG", "Backlog"),
    ("CARDS_INPROGRESS", "InProgress"),
    ("CARDS_DONE", "Done"),
    ("CARDS_BLOCKED", "Blocked"),
)

# Tailwind class strings for the MoSCoW badge column. Static set so the
# Tailwind CDN JIT picks every concrete class up at first paint.
MOSCOW_BADGE_CLASSES: dict[str, str] = {
    "Must":   "bg-purple-100 text-purple-900",
    "Should": "bg-sky-100 text-sky-900",
    "Could":  "bg-amber-100 text-amber-900",
    "Wont":   "bg-slate-200 text-slate-700",
}


def _esc(value: Any) -> str:
    """HTML-escape a value (quotes included). None coerces to empty string."""
    if value is None:
        return ""
    if not isinstance(value, str):
        value = str(value)
    return html.escape(value, quote=True)


def _scalar(template: str, key: str, value: str) -> str:
    """Replace every ``__KEY__`` occurrence with ``value`` (already escaped)."""
    return template.replace(f"__{key}__", value)


def _block_re(name: str) -> re.Pattern[str]:
    """Compile a regex matching one named TEMPLATE block with body capture."""
    return re.compile(
        r"<!--\s*TEMPLATE:" + re.escape(name) + r"\s*-->"
        r"(?P<body>.*?)"
        r"<!--\s*/TEMPLATE:" + re.escape(name) + r"\s*-->",
        re.DOTALL,
    )


def _drop_block(template: str, name: str) -> str:
    """Drop a named TEMPLATE block entirely (used for unmet IFEMPTY/IFANY)."""
    return _block_re(name).sub("", template, count=1)


def _strip_delimiters(template: str, name: str) -> str:
    """Remove only the TEMPLATE:NAME delimiters, keeping the body intact."""
    opening = re.compile(r"<!--\s*TEMPLATE:" + re.escape(name) + r"\s*-->")
    closing = re.compile(r"<!--\s*/TEMPLATE:" + re.escape(name) + r"\s*-->")
    return closing.sub("", opening.sub("", template, count=1), count=1)


def _format_rice(score: float | None) -> str:
    """Pretty-print a RICE score; empty for None; trim trailing .0 when integer."""
    if score is None:
        return ""
    return str(int(score)) if score == int(score) else f"{score:.1f}"


def _format_warning_bound(warning: dict[str, Any]) -> str:
    """Render-ready 'bound' label for a warning: card_id, else path, else empty."""
    if warning.get("card_id"):
        return _esc(warning["card_id"])
    if warning.get("path"):
        return _esc(warning["path"])
    return ""


def _expand_block(
    template: str,
    name: str,
    items: list[dict[str, Any]],
    *,
    field_map: dict[str, str] | None = None,
    raw_keys: tuple[str, ...] = (),
    fallback_empty_name: str | None = None,
) -> str:
    """Expand one TEMPLATE block once per item; handle IFEMPTY companion.

    ``field_map``  maps template placeholder name (UPPER_SNAKE without underscores)
                   to item dict key. Values are HTML-escaped.
    ``raw_keys``   placeholders whose value is pre-rendered HTML and must NOT
                   be re-escaped (e.g. METRIC_CURRENT_HTML, WARNING_BOUND_HTML).
                   The corresponding dict key matches the placeholder verbatim.
    """
    pattern = _block_re(name)
    match = pattern.search(template)
    if match is None:
        return template
    body = match.group("body")
    if items:
        chunks: list[str] = []
        for item in items:
            chunk = body
            if field_map:
                for placeholder, item_key in field_map.items():
                    chunk = chunk.replace(f"__{placeholder}__", _esc(item.get(item_key)))
            for raw_key in raw_keys:
                chunk = chunk.replace(f"__{raw_key}__", str(item.get(raw_key, "")))
            chunks.append(chunk)
        replacement = "".join(chunks)
        template = pattern.sub(lambda _: replacement, template, count=1)
        if fallback_empty_name is not None:
            template = _drop_block(template, fallback_empty_name)
    else:
        template = _drop_block(template, name)
        if fallback_empty_name is not None:
            template = _strip_delimiters(template, fallback_empty_name)
    return template


def _card_field_map(card: dict[str, Any]) -> dict[str, str]:
    """Pre-escape every per-card placeholder value used in the board cards."""
    return {
        "CARD_ID": _esc(card["id"]),
        "CARD_TITLE": _esc(card["title"]),
        "CARD_MOSCOW": _esc(card["moscow"]),
        "CARD_TYPE": _esc(card["type"] or ""),
        "CARD_CYCLE": _esc(card["cycle"] or ""),
        "MOSCOW_BADGE_CLASSES": _esc(MOSCOW_BADGE_CLASSES.get(card["moscow"], "")),
        "RICE_SCORE": _esc(_format_rice(card["rice"].get("score"))),
        "STORY_POINTS": _esc(card.get("story_points") or ""),
    }


def _expand_cards_blocks(template: str, by_status: dict[str, list[dict[str, Any]]]) -> str:
    """Expand the four CARDS_<STATUS> blocks plus their IFEMPTY counterparts."""
    for block_name, status in _STATUS_COLUMNS:
        items = by_status[status]
        pattern = _block_re(block_name)
        match = pattern.search(template)
        if match is None:
            continue
        body = match.group("body")
        if items:
            chunks: list[str] = []
            for card in items:
                chunk = body
                for placeholder, value in _card_field_map(card).items():
                    chunk = chunk.replace(f"__{placeholder}__", value)
                chunks.append(chunk)
            replacement = "".join(chunks)
            template = pattern.sub(lambda _: replacement, template, count=1)
            template = _drop_block(template, f"IFEMPTY_{block_name}")
        else:
            template = _drop_block(template, block_name)
            template = _strip_delimiters(template, f"IFEMPTY_{block_name}")
    return template


def _build_metrics_items(success_metrics: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Pre-render the optional METRIC_CURRENT_HTML span for each metric."""
    items: list[dict[str, Any]] = []
    for metric in success_metrics:
        current = metric.get("current")
        if current is not None and str(current).strip():
            current_html = f'<span class="ml-2 text-slate-500">(current: {_esc(current)})</span>'
        else:
            current_html = ""
        items.append({
            "METRIC_NAME": metric["name"],
            "METRIC_TARGET": metric["target"],
            "METRIC_CURRENT_HTML": current_html,
        })
    return items


def _build_warning_items(warnings_list: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Build per-warning items. ``code`` / ``message`` route via field_map and
    get escaped at expansion time; ``WARNING_BOUND_HTML`` is pre-escaped and
    routed via raw_keys to skip a redundant escape pass.
    """
    return [
        {
            "code": w["code"],
            "message": w["message"],
            "WARNING_BOUND_HTML": _format_warning_bound(w),
        }
        for w in warnings_list
    ]


def hydrate(template_path: Path, envelope: dict[str, Any]) -> str:
    """Merge the template + envelope into a hydrated HTML string.

    Order of operations matters: iterables expand first so their bodies cannot
    collide with top-level scalar substitution downstream.
    """
    template = template_path.read_text(encoding="utf-8")

    cards: list[dict[str, Any]] = envelope["cards"]
    reviews: list[dict[str, Any]] = envelope["reviews"]
    warnings_list: list[dict[str, Any]] = envelope["warnings"]
    meta = envelope["project_meta"]

    # Partition cards by status; WONT excluded from the board entirely.
    by_status: dict[str, list[dict[str, Any]]] = {
        "Backlog": [], "InProgress": [], "Done": [], "Blocked": [],
    }
    for card in cards:
        if card["moscow"] == "Wont":
            continue
        by_status[card["status"]].append(card)

    template = _expand_cards_blocks(template, by_status)
    count_map = (
        ("BACKLOG", "Backlog"),
        ("INPROGRESS", "InProgress"),
        ("DONE", "Done"),
        ("BLOCKED", "Blocked"),
    )
    for placeholder_suffix, status_key in count_map:
        template = _scalar(template, f"COUNT_{placeholder_suffix}", _esc(len(by_status[status_key])))

    # Objectives.
    template = _expand_block(
        template, "OBJECTIVES",
        items=[{"text": o} for o in meta["objectives"]],
        field_map={"OBJECTIVE_TEXT": "text"},
        fallback_empty_name="IFEMPTY_OBJECTIVES",
    )

    # Stakeholders.
    template = _expand_block(
        template, "STAKEHOLDERS",
        items=meta["stakeholders"],
        field_map={"STAKEHOLDER_NAME": "name", "STAKEHOLDER_ROLE": "role"},
        fallback_empty_name="IFEMPTY_STAKEHOLDERS",
    )

    # Success metrics (METRIC_CURRENT_HTML is pre-rendered, not re-escaped).
    template = _expand_block(
        template, "SUCCESS_METRICS",
        items=_build_metrics_items(meta["success_metrics"]),
        raw_keys=("METRIC_NAME", "METRIC_TARGET", "METRIC_CURRENT_HTML"),
        fallback_empty_name="IFEMPTY_SUCCESS_METRICS",
    )

    # Reviews.
    template = _expand_block(
        template, "REVIEWS",
        items=[{"cycle": r["cycle"], "file": r["file"], "summary": r["summary"]} for r in reviews],
        field_map={"REVIEW_CYCLE": "cycle", "REVIEW_FILE": "file", "REVIEW_SUMMARY": "summary"},
        fallback_empty_name="IFEMPTY_REVIEWS",
    )

    # Warnings panel inside an IFANY_WARNINGS wrapper. ``code`` / ``message``
    # are user-visible and routed via field_map to be HTML-escaped at expand
    # time; ``WARNING_BOUND_HTML`` is pre-escaped scalar text.
    if warnings_list:
        template = _expand_block(
            template, "WARNINGS",
            items=_build_warning_items(warnings_list),
            field_map={"WARNING_CODE": "code", "WARNING_MESSAGE": "message"},
            raw_keys=("WARNING_BOUND_HTML",),
        )
        template = _strip_delimiters(template, "IFANY_WARNINGS")
    else:
        template = _drop_block(template, "IFANY_WARNINGS")

    # Top-level scalars last.
    template = _scalar(template, "PROJECT_NAME", _esc(meta["name"]))
    template = _scalar(template, "GENERATED_AT", _esc(envelope["generated_at"]))
    template = _scalar(template, "SCHEMA_VERSION", _esc(envelope["schema_version"]))
    template = _scalar(template, "BACKLOG_PATH", _esc(envelope["source"]["backlog_path"]))
    template = _scalar(template, "ML_PROBLEM_STATEMENT", _esc(meta["ml_problem_statement"]))

    return template
