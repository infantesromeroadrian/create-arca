#!/usr/bin/env python3
"""ARCA dashboard-build parser core (T11).

Implements the canonical-table backlog parser described in
``docs/specs/dashboard-build/parser-contract.md`` (schema 1.0.0). Invoked from
``skills/dashboard-build/run.sh`` as a child process; never owns argv handling
beyond what is needed for ``--self-check`` integration tests.

Outputs:
    --mode json  -> JSON document on stdout matching docs/specs/dashboard-build/schema.json
    --mode html  -> Hydrated HTML on stdout (template + JSON merged, HTML-escaped)

Logging goes to stderr exclusively. stdout carries only the produced artefact
so the skill can pipe it to jq / a file without exit-code gymnastics.

Exit codes mirror the parser-contract.md Exit code catalogue. The skill-side
exits (100/101/102) are validated by run.sh BEFORE this script runs.

HTML hydration lives in ``_lib/hydrator.py`` so this module stays under the
T11 800-LOC budget. Errors are defined in ``_lib/errors.py``.

TODO(T11-followup-LOC-split): this module is currently 930 LOC (over the 800
cap accepted as Wave-4 debt per SKILL.md). Planned reduction: extract
``_normalise_*`` family (cycle, MoSCoW header, story_points, slash-types, id
case, header aliases) to ``_lib/normalise.py`` and ``_parse_sidecar_*`` family
(problem-statement, success-metrics, stakeholders, objectives) to
``_lib/sidecars.py``. Target post-split: parser-core.py ~600 LOC. Tracked as
follow-up task to T11; not blocking Wave-4 closure.

TODO(T11-followup-tarjan-iter): ``_detect_cycles`` uses recursive Tarjan SCC.
sys.setrecursionlimit raises the ceiling but cannot defeat the OS stack-frame
limit beyond ~2000 cards. Rewrite as iterative-stack Tarjan when backlogs
grow past that scale (C8+ on mature projects). Not blocking T11; W110 path
remains correct for typical C1-C6 backlog sizes.
"""

from __future__ import annotations

import argparse
import json
import logging
import re
import sys
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

# Make _lib importable regardless of cwd: parser-core.py is loaded by run.sh
# from an arbitrary working directory.
_HERE = Path(__file__).resolve().parent
if str(_HERE) not in sys.path:
    sys.path.insert(0, str(_HERE))

from _lib import hydrator  # noqa: E402 -- sys.path fix above is intentional
from _lib.errors import (  # noqa: E402
    CardDropped,
    E101BacklogMissing,
    E102BacklogEncoding,
    E103YamlFrontmatter,
    E104NoMustHeader,
    E201TableHeader,
    E202DuplicateId,
    E203UnresolvedDep,
    E204BadId,
    E205BadCycle,
    E206BadType,
    E207BadImpact,
    E208BadConfidence,
    E209BadReachEffort,
    E210BadStoryPoints,
    E301WontHeader,
    E401TemplateMissing,
    E403StatusOverlayMalformed,
    E901SelfCheck,
    ParserError,
)

SCHEMA_VERSION = "1.0.0"

CANONICAL_TABLE_HEADER: tuple[str, ...] = (
    "ID", "Title", "Type", "Cycle", "Story pts",
    "Reach", "Impact", "Conf", "Effort (d)", "RICE", "Deps",
)
WONT_TABLE_HEADER: tuple[str, ...] = ("ID", "Title", "Reason")

TYPE_ENUM: frozenset[str] = frozenset({
    "Data", "Model", "Infra", "Eval", "Docs",
    "Spike", "Integration", "Security", "UI", "Research",
})

CYCLE_RE = re.compile(r"^C(?:1[0-4]|[1-9])(?:→C(?:1[0-4]|[1-9]))?$")
FIB_SET: frozenset[str] = frozenset({"1", "2", "3", "5", "8", "13"})
IMPACT_ENUM: frozenset[float] = frozenset({3.0, 2.0, 1.0, 0.5, 0.25})
STATUS_VALID: frozenset[str] = frozenset({"Backlog", "InProgress", "Done", "Blocked"})
REVIEW_FILE_RE = re.compile(r"^architect-review-C(?P<cycle>\d{1,2})\.md$")
REVIEW_SUMMARY_MAXLEN = 200

MOSCOW_HEADER_RE = re.compile(
    r"^###\s+(MUST|SHOULD|COULD|WON'?T|WONT)(\s*\(.*\))?\s*$",
    re.IGNORECASE,
)
MOSCOW_NORMALISE: dict[str, str] = {
    "MUST": "Must", "SHOULD": "Should", "COULD": "Could",
    "WONT": "Wont",
}
ID_RE = re.compile(r"^BL-(\d{3})$")

logger = logging.getLogger("dashboard-build.parser-core")


@dataclass(frozen=True, slots=True)
class Warning_:
    """One non-fatal warning record matching schema.warnings[]."""

    code: str
    message: str
    card_id: str | None = None
    path: str | None = None

    def to_dict(self) -> dict[str, Any]:
        payload: dict[str, Any] = {"code": self.code, "message": self.message}
        if self.card_id is not None:
            payload["card_id"] = self.card_id
        if self.path is not None:
            payload["path"] = self.path
        return payload


@dataclass(slots=True)
class WarningSink:
    """Mutable accumulator; emitted in discovery order at the end of the run."""

    items: list[Warning_] = field(default_factory=list)
    # Per-card range provenance for E203 attribution when a range expansion
    # produces an undefined ID inside [left_n, right_n].
    ranges_by_card: dict[str, list[tuple[str, int, int]]] = field(default_factory=dict)

    def add(self, code: str, message: str, *, card_id: str | None = None,
            path: str | None = None) -> None:
        self.items.append(Warning_(code=code, message=message, card_id=card_id, path=path))

    def as_list(self) -> list[dict[str, Any]]:
        return [w.to_dict() for w in self.items]


# --------------------------------------------------------------------------- #
# Markdown table walking                                                      #
# --------------------------------------------------------------------------- #

def _read_text(path: Path) -> str:
    """Read a file as strict UTF-8; surfaces E102 on decode failure."""
    try:
        return path.read_text(encoding="utf-8")
    except UnicodeDecodeError as exc:
        raise E102BacklogEncoding(f"{path} is not valid UTF-8: {exc}") from exc


def _split_table_row(line: str) -> list[str]:
    """Split a Markdown table row, stripping leading/trailing pipes and cells."""
    stripped = line.strip()
    if stripped.startswith("|"):
        stripped = stripped[1:]
    if stripped.endswith("|"):
        stripped = stripped[:-1]
    return [cell.strip() for cell in stripped.split("|")]


def _is_separator_row(cells: list[str]) -> bool:
    """Markdown alignment row: every cell is dashes / colons only."""
    return bool(cells) and all(re.fullmatch(r":?-{3,}:?", c.strip()) for c in cells)


def _first_non_empty_paragraph(text: str) -> str:
    """First non-empty paragraph after any leading H1. Used for summaries."""
    lines = text.splitlines()
    idx = 0
    if idx < len(lines) and lines[idx].startswith("# "):
        idx += 1
    paragraph: list[str] = []
    while idx < len(lines):
        line = lines[idx].rstrip()
        if line:
            paragraph.append(line)
        elif paragraph:
            break
        idx += 1
    return " ".join(paragraph).strip()


@dataclass(slots=True)
class _Section:
    """A MoSCoW H3 section with raw rows captured for downstream parsing."""

    moscow: str
    header_row: list[str] | None
    data_rows: list[tuple[int, list[str]]]


def _scan_sections(text: str) -> list[_Section]:
    """Walk the backlog markdown, collecting MoSCoW sections + table rows."""
    sections: list[_Section] = []
    current: _Section | None = None
    expecting_header = False
    expecting_separator = False

    for lineno, raw in enumerate(text.splitlines(), start=1):
        line = raw.rstrip()
        match = MOSCOW_HEADER_RE.match(line)
        if match:
            key = match.group(1).upper().replace("'", "")
            current = _Section(moscow=MOSCOW_NORMALISE[key], header_row=None, data_rows=[])
            sections.append(current)
            expecting_header = True
            expecting_separator = False
            continue
        if line.startswith("#"):
            current = None
            expecting_header = False
            expecting_separator = False
            continue
        if current is None or not line.startswith("|"):
            continue
        cells = _split_table_row(line)
        if expecting_header:
            current.header_row = cells
            expecting_header = False
            expecting_separator = True
            continue
        if expecting_separator:
            expecting_separator = False
            if _is_separator_row(cells):
                continue
        if _is_separator_row(cells):
            continue
        current.data_rows.append((lineno, cells))

    return sections


def _validate_header(section: _Section) -> None:
    """Compare a section header row against the canonical for its MoSCoW type."""
    if section.header_row is None:
        if section.data_rows:
            raise E201TableHeader(
                f"section '{section.moscow}' has data rows but no header row"
            )
        return
    expected = WONT_TABLE_HEADER if section.moscow == "Wont" else CANONICAL_TABLE_HEADER
    err_cls: type[ParserError] = E301WontHeader if section.moscow == "Wont" else E201TableHeader
    if tuple(section.header_row) != expected:
        raise err_cls(
            f"{section.moscow} table header mismatch.\n"
            f"  expected: | {' | '.join(expected)} |\n"
            f"  got:      | {' | '.join(section.header_row)} |"
        )


# --------------------------------------------------------------------------- #
# Cell-level normalisation                                                    #
# --------------------------------------------------------------------------- #

def _normalise_id(raw: str, line: int) -> str:
    """Normalise BL-NNN id; case-insensitive prefix per parser-contract."""
    candidate = raw.strip()
    if not candidate:
        raise E204BadId(f"line {line}: empty card ID")
    if candidate[:3].lower() == "bl-":
        candidate = "BL-" + candidate[3:]
    if not ID_RE.match(candidate):
        raise E204BadId(f"line {line}: ID '{raw}' does not match BL-NNN")
    return candidate


def _normalise_cycle(raw: str, card_id: str, sink: WarningSink) -> str:
    """Normalise cycle string; W102 when surface form needed cleanup."""
    original = raw
    candidate = raw.strip()
    candidate = re.sub(r"\s*(?:->|→)\s*", "→", candidate)
    candidate = re.sub(r"\bc(\d)", r"C\1", candidate)
    if candidate != original:
        sink.add("W102", f"cycle '{original}' normalised to '{candidate}'", card_id=card_id)
    if not CYCLE_RE.match(candidate):
        raise E205BadCycle(f"{card_id}: cycle '{raw}' outside ADR-040 section 1.4 enum")
    if "→" in candidate:
        left, right = candidate.split("→")
        if int(left[1:]) >= int(right[1:]):
            sink.add("W402", f"cycle range '{candidate}' inverted; card dropped", card_id=card_id)
            raise CardDropped(card_id)
    return candidate


def _normalise_type(raw: str, card_id: str, sink: WarningSink) -> str:
    """Normalise type cell; canonicalises slash combos alphabetically."""
    candidate = raw.strip()
    if not candidate:
        raise E206BadType(f"{card_id}: empty type cell")
    parts = re.split(r"\s*[/\-]\s*", candidate)
    canonical_parts = sorted(parts)
    out_of_enum = [p for p in canonical_parts if p not in TYPE_ENUM]
    if out_of_enum:
        if len(canonical_parts) == 1:
            raise E206BadType(f"{card_id}: type '{raw}' outside ADR-040 section 1.3 enum")
        sink.add(
            "W103",
            f"type '{raw}' contains unknown half {out_of_enum}; accepted with caveat",
            card_id=card_id,
        )
    return "/".join(canonical_parts)


def _parse_int(raw: str, card_id: str, field_name: str) -> int:
    try:
        return int(raw.strip())
    except ValueError as exc:
        raise E209BadReachEffort(f"{card_id}: {field_name} '{raw}' not an integer") from exc


def _parse_float(raw: str, card_id: str, field_name: str) -> float:
    try:
        return float(raw.strip())
    except ValueError as exc:
        raise E209BadReachEffort(f"{card_id}: {field_name} '{raw}' not a number") from exc


def _normalise_story_points(raw: str, card_id: str) -> str:
    """Normalise story-points string. Strict mode: must be Fibonacci."""
    candidate = raw.strip()
    if re.fullmatch(r"\d+\.0", candidate):
        candidate = candidate[:-2]
    if re.fullmatch(r"\d+", candidate):
        if candidate not in FIB_SET:
            raise E210BadStoryPoints(f"{card_id}: story_points '{raw}' not in Fibonacci")
        return candidate
    if re.fullmatch(r"\d+-\d+", candidate):
        left, right = candidate.split("-")
        if left not in FIB_SET or right not in FIB_SET:
            raise E210BadStoryPoints(f"{card_id}: story_points range '{raw}' not Fibonacci")
        return candidate
    raise E210BadStoryPoints(f"{card_id}: story_points '{raw}' malformed")


def _parse_dependencies(raw: str, card_id: str, sink: WarningSink) -> list[str]:
    """Expand singles, comma lists, and ranges into a deduped ID list."""
    stripped = raw.strip()
    if stripped in ("", "-", "—"):
        return []
    out: list[str] = []
    seen: set[str] = set()
    for token in re.split(r"\s*,\s*", stripped):
        if not token:
            continue
        if ".." in token:
            left, _, right = token.partition("..")
            try:
                left_id = _normalise_id(left, 0)
                right_id = _normalise_id(right, 0)
            except E204BadId as exc:
                raise E203UnresolvedDep(
                    f"{card_id}: dependency range '{token}' malformed: {exc}"
                ) from exc
            left_n, right_n = int(left_id[3:]), int(right_id[3:])
            if right_n <= left_n:
                sink.add(
                    "W401",
                    f"range '{token}' has end <= start; skipped, no expansion",
                    card_id=card_id,
                )
                continue
            for n in range(left_n, right_n + 1):
                dep_id = f"BL-{n:03d}"
                if dep_id not in seen:
                    seen.add(dep_id)
                    out.append(dep_id)
            sink.ranges_by_card.setdefault(card_id, []).append((token, left_n, right_n))
        else:
            try:
                normalised = _normalise_id(token, 0)
            except E204BadId as exc:
                raise E203UnresolvedDep(
                    f"{card_id}: dependency '{token}' malformed: {exc}"
                ) from exc
            if normalised not in seen:
                seen.add(normalised)
                out.append(normalised)
    return out


# --------------------------------------------------------------------------- #
# Card construction                                                           #
# --------------------------------------------------------------------------- #

def _build_card_from_row(  # noqa: PLR0912 - mirrors schema column count
    cells: list[str],
    *,
    moscow: str,
    line: int,
    sink: WarningSink,
) -> dict[str, Any]:
    """Build a non-WONT card dict from one canonical-table data row."""
    if len(cells) != len(CANONICAL_TABLE_HEADER):
        raise E201TableHeader(
            f"line {line}: row has {len(cells)} cells, expected {len(CANONICAL_TABLE_HEADER)}"
        )
    (raw_id, raw_title, raw_type, raw_cycle, raw_sp,
     raw_reach, raw_impact, raw_conf, raw_effort, raw_rice, raw_deps) = cells

    card_id = _normalise_id(raw_id, line)
    title = raw_title.rstrip()
    if not title:
        raise E201TableHeader(f"{card_id} (line {line}): empty Title cell")
    card_type = _normalise_type(raw_type, card_id, sink)
    cycle = _normalise_cycle(raw_cycle, card_id, sink)
    story_points = _normalise_story_points(raw_sp, card_id)

    reach = _parse_int(raw_reach, card_id, "reach")
    if reach < 1:
        raise E209BadReachEffort(f"{card_id}: reach {reach} not >= 1")
    impact = _parse_float(raw_impact, card_id, "impact")
    if impact not in IMPACT_ENUM:
        raise E207BadImpact(f"{card_id}: impact {raw_impact} not in {{3,2,1,0.5,0.25}}")
    confidence = _parse_float(raw_conf, card_id, "confidence")
    if not 0 <= confidence <= 1:
        raise E208BadConfidence(f"{card_id}: confidence {raw_conf} outside [0,1]")
    effort = _parse_float(raw_effort, card_id, "effort")
    if effort <= 0:
        raise E209BadReachEffort(f"{card_id}: effort {effort} not > 0")
    score = _parse_float(raw_rice, card_id, "RICE")
    if score <= 0:
        raise E209BadReachEffort(f"{card_id}: RICE score {score} not > 0")

    computed = reach * impact * confidence / effort
    if abs(computed - score) > 0.5:
        sink.add(
            "W104",
            f"rice.score {score} diverges from computed {computed:.3f} by > 0.5",
            card_id=card_id,
        )
    if confidence not in {1.0, 0.8, 0.5}:
        sink.add(
            "W105",
            f"confidence {confidence} outside canonical {{1.0, 0.8, 0.5}}",
            card_id=card_id,
        )

    return {
        "id": card_id,
        "title": title,
        "status": "Backlog",
        "moscow": moscow,
        "type": card_type,
        "cycle": cycle,
        "story_points": story_points,
        "rice": {
            "reach": reach,
            "impact": impact,
            "confidence": confidence,
            "effort": effort,
            "score": score,
        },
        "dependencies": _parse_dependencies(raw_deps, card_id, sink),
    }


def _build_wont_card(cells: list[str], *, line: int) -> dict[str, Any]:
    """Build a WONT card dict from one 3-column reduced row."""
    if len(cells) != len(WONT_TABLE_HEADER):
        raise E301WontHeader(
            f"line {line}: WONT row has {len(cells)} cells, expected {len(WONT_TABLE_HEADER)}"
        )
    raw_id, raw_title, raw_reason = cells
    card_id = _normalise_id(raw_id, line)
    title = raw_title.rstrip()
    if not title:
        raise E301WontHeader(f"{card_id} (line {line}): empty Title cell in WONT row")
    reason = raw_reason.rstrip()
    if not reason:
        raise E301WontHeader(f"{card_id} (line {line}): empty Reason cell in WONT row")
    return {
        "id": card_id,
        "title": title,
        "status": "Backlog",
        "moscow": "Wont",
        "type": None,
        "cycle": None,
        "story_points": None,
        "rice": {"reach": None, "impact": None, "confidence": None, "effort": None, "score": None},
        "dependencies": [],
        "won_reason": reason,
    }


# --------------------------------------------------------------------------- #
# Sidecar parsing                                                             #
# --------------------------------------------------------------------------- #

def _parse_objectives(path: Path) -> list[str]:
    """One bullet per objective; ignores headers and blanks."""
    out: list[str] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        match = re.match(r"^\s*[-*]\s+(.+)$", line)
        if match:
            out.append(match.group(1).strip())
    return out


def _parse_stakeholders(path: Path) -> list[dict[str, str]]:
    """Each `- name -- role`; em-dash, en-dash, or ASCII '--' accepted."""
    out: list[dict[str, str]] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        match = re.match(
            r"^\s*[-*]\s+(?P<name>.+?)\s+[—–\-]+\s+(?P<role>.+)$",
            line,
        )
        if match:
            name = match.group("name").strip()
            role = match.group("role").strip()
            if name and role:
                out.append({"name": name, "role": role})
    return out


def _parse_success_metrics(path: Path) -> list[dict[str, Any]]:
    """One `- name: target` per line; optional `(current: <value>)` suffix."""
    out: list[dict[str, Any]] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        match = re.match(
            r"^\s*[-*]\s+(?P<name>[^:]+?):\s+(?P<target>[^()]+?)"
            r"(?:\s*\(current:\s*(?P<current>[^)]+?)\))?\s*$",
            line,
        )
        if match:
            name = match.group("name").strip()
            target = match.group("target").strip()
            current = match.group("current")
            if name and target:
                entry: dict[str, Any] = {
                    "name": name,
                    "target": target,
                    "current": current.strip() if current and current.strip() else None,
                }
                out.append(entry)
    return out


def _parse_problem_statement(path: Path) -> str:
    return _first_non_empty_paragraph(path.read_text(encoding="utf-8"))


# --------------------------------------------------------------------------- #
# Reviews scanning                                                            #
# --------------------------------------------------------------------------- #

def _scan_reviews(reviews_dir: Path, project_root: Path,
                  sink: WarningSink) -> list[dict[str, Any]]:
    """Scan architecture review files; emit one entry per valid cycle filename."""
    if not reviews_dir.is_dir():
        return []
    entries: list[tuple[int, dict[str, Any]]] = []
    for child in sorted(reviews_dir.iterdir()):
        if not child.is_file():
            continue
        match = REVIEW_FILE_RE.match(child.name)
        if not match:
            continue
        cycle_n = int(match.group("cycle"))
        rel_path = str(child.relative_to(project_root))
        if not 1 <= cycle_n <= 14:
            sink.add("W301", f"review cycle {cycle_n} outside 1..14; skipped", path=rel_path)
            continue
        body = child.read_text(encoding="utf-8")
        summary = _first_non_empty_paragraph(body)
        if not summary:
            sink.add("W302", "review file empty", path=rel_path)
        elif len(summary) > REVIEW_SUMMARY_MAXLEN:
            summary = summary[: REVIEW_SUMMARY_MAXLEN - 1].rstrip() + "…"
        entries.append((cycle_n, {"cycle": cycle_n, "file": rel_path, "summary": summary}))
    entries.sort(key=lambda pair: pair[0])
    return [entry for _, entry in entries]


# --------------------------------------------------------------------------- #
# Status overlay                                                              #
# --------------------------------------------------------------------------- #

def _apply_status_overlay(cards: list[dict[str, Any]], overlay_path: Path,
                          sink: WarningSink) -> None:
    """Merge ``.dashboard/status.json`` overlay into the cards list in place."""
    if not overlay_path.is_file():
        return
    try:
        raw = overlay_path.read_text(encoding="utf-8")
    except UnicodeDecodeError as exc:
        raise E403StatusOverlayMalformed(f"status overlay not valid UTF-8: {exc}") from exc
    try:
        data = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise E403StatusOverlayMalformed(
            f"{overlay_path}: malformed JSON at line {exc.lineno} col {exc.colno}: {exc.msg}"
        ) from exc
    if not isinstance(data, dict):
        raise E403StatusOverlayMalformed(
            f"{overlay_path}: top-level must be an object, got {type(data).__name__}"
        )
    cards_by_id: dict[str, dict[str, Any]] = {c["id"]: c for c in cards}
    for raw_key, entry in data.items():
        try:
            card_id = _normalise_id(raw_key, 0)
        except E204BadId:
            sink.add("W108", f"status overlay key '{raw_key}' is not a valid BL-NNN id")
            continue
        if card_id not in cards_by_id:
            sink.add("W108", f"status overlay references unknown card '{card_id}'",
                     card_id=card_id)
            continue
        if not isinstance(entry, dict):
            sink.add("W109", f"status overlay for {card_id} is not an object; ignored",
                     card_id=card_id)
            continue
        card = cards_by_id[card_id]
        status = entry.get("status")
        if card["moscow"] != "Wont" and isinstance(status, str):
            if status in STATUS_VALID:
                card["status"] = status
            else:
                sink.add(
                    "W109",
                    f"status overlay value '{status}' not in {sorted(STATUS_VALID)}; fallback Backlog",
                    card_id=card_id,
                )
        owner = entry.get("owner")
        if isinstance(owner, str) and owner.strip():
            card["owner"] = owner.strip()


# --------------------------------------------------------------------------- #
# Cyclic dependency detection (Tarjan SCC)                                    #
# --------------------------------------------------------------------------- #

def _detect_cycles(cards: list[dict[str, Any]], sink: WarningSink) -> None:
    """Tarjan SCC over the dep graph; emit W110 per card in any cycle."""
    index_counter = [0]
    stack: list[str] = []
    on_stack: set[str] = set()
    indices: dict[str, int] = {}
    lowlinks: dict[str, int] = {}
    sccs: list[list[str]] = []
    graph: dict[str, list[str]] = {c["id"]: list(c["dependencies"]) for c in cards}

    def strongconnect(node: str) -> None:
        indices[node] = index_counter[0]
        lowlinks[node] = index_counter[0]
        index_counter[0] += 1
        stack.append(node)
        on_stack.add(node)
        for nbr in graph.get(node, []):
            if nbr not in indices:
                strongconnect(nbr)
                lowlinks[node] = min(lowlinks[node], lowlinks[nbr])
            elif nbr in on_stack:
                lowlinks[node] = min(lowlinks[node], indices[nbr])
        if lowlinks[node] == indices[node]:
            component: list[str] = []
            while True:
                top = stack.pop()
                on_stack.discard(top)
                component.append(top)
                if top == node:
                    break
            sccs.append(component)

    sys.setrecursionlimit(max(1000, sys.getrecursionlimit(), len(cards) * 4 + 100))
    for cid in graph:
        if cid not in indices:
            strongconnect(cid)

    for component in sccs:
        if len(component) == 1:
            only = component[0]
            if only in graph.get(only, []):
                sink.add("W110", f"Cyclic dependency: {only} -> {only}", card_id=only)
            continue
        ordered = sorted(component)
        cycle_chain = " -> ".join([*ordered, ordered[0]])
        for member in ordered:
            sink.add("W110", f"Cyclic dependency: {cycle_chain}", card_id=member)


# --------------------------------------------------------------------------- #
# Dependency validation                                                       #
# --------------------------------------------------------------------------- #

def _validate_dependencies(cards: list[dict[str, Any]], sink: WarningSink) -> None:
    """Every dep ID must exist in the cards set; cite range syntax on misses."""
    known: set[str] = {c["id"] for c in cards}
    for card in cards:
        for dep in card["dependencies"]:
            if dep in known:
                continue
            dep_n = int(dep[3:])
            for token, left_n, right_n in sink.ranges_by_card.get(card["id"], []):
                if left_n <= dep_n <= right_n:
                    raise E203UnresolvedDep(
                        f"dependency range {token} contains undefined card {dep}"
                    )
            raise E203UnresolvedDep(
                f"{card['id']} depends on {dep}, which is not defined in the backlog"
            )


# --------------------------------------------------------------------------- #
# Top-level pipeline                                                          #
# --------------------------------------------------------------------------- #

def _parse_backlog(text: str, sink: WarningSink) -> tuple[str, list[dict[str, Any]]]:
    """Parse backlog markdown text into (project_name_from_h1, cards)."""
    name_from_h1 = ""
    for line in text.splitlines():
        if line.startswith("# "):
            name_from_h1 = re.sub(r"\s*[—–\-]+\s*Backlog\s*$", "", line[2:].strip())
            break

    sections = _scan_sections(text)
    if not any(s.moscow == "Must" for s in sections):
        raise E104NoMustHeader("no '### MUST' header found in backlog")

    cards: list[dict[str, Any]] = []
    seen_ids: set[str] = set()

    for section in sections:
        _validate_header(section)
        for line, cells in section.data_rows:
            try:
                card = (
                    _build_wont_card(cells, line=line)
                    if section.moscow == "Wont"
                    else _build_card_from_row(cells, moscow=section.moscow, line=line, sink=sink)
                )
            except CardDropped:
                continue
            if card["id"] in seen_ids:
                raise E202DuplicateId(f"duplicate card ID {card['id']} at line {line}")
            seen_ids.add(card["id"])
            cards.append(card)

    return name_from_h1, cards


def _build_envelope(  # noqa: PLR0913 - shape mirrors the schema top level
    *,
    project_root: Path,
    project_name: str,
    cards: list[dict[str, Any]],
    extras: dict[str, Any],
    reviews: list[dict[str, Any]],
    presence: dict[str, bool],
    warnings_list: list[dict[str, Any]],
) -> dict[str, Any]:
    """Assemble the schema-conformant top-level JSON object."""
    sidecar_records = (
        ("problem_statement", "docs/c1-discovery/problem-statement.md", presence["problem"]),
        ("success_metrics",   "docs/c1-discovery/success-metrics.md",   presence["metrics"]),
        ("stakeholders",      "docs/c1-discovery/stakeholders.md",      presence["stake"]),
        ("objectives",        "docs/c1-discovery/objectives.md",        presence["obj"]),
    )
    return {
        "schema_version": SCHEMA_VERSION,
        "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "source": {
            "backlog_path": "docs/c1-discovery/backlog.md",
            "project_root": str(project_root),
            "sidecars": [
                {"kind": kind, "path": rel, "present": ok}
                for kind, rel, ok in sidecar_records
            ],
        },
        "project_meta": {
            "name": project_name,
            "objectives": extras.get("objectives", []),
            "stakeholders": extras.get("stakeholders", []),
            "ml_problem_statement": extras.get("ml_problem_statement", ""),
            "success_metrics": extras.get("success_metrics", []),
        },
        "cards": cards,
        "reviews": reviews,
        "warnings": warnings_list,
    }


def _ingest_sidecars(project_root: Path, sink: WarningSink) -> tuple[dict[str, bool], dict[str, Any]]:
    """Read the four optional sidecars; return (presence, extras_for_meta)."""
    sidecar_dir = project_root / "docs" / "c1-discovery"
    presence = {"problem": False, "metrics": False, "stake": False, "obj": False}
    extras: dict[str, Any] = {}

    pairs: tuple[tuple[str, str, str, str], ...] = (
        ("problem", "problem-statement.md", "W201", "ml_problem_statement"),
        ("metrics", "success-metrics.md",   "W202", "success_metrics"),
        ("stake",   "stakeholders.md",      "W203", "stakeholders"),
        ("obj",     "objectives.md",        "W204", "objectives"),
    )
    parsers = {
        "problem": _parse_problem_statement,
        "metrics": _parse_success_metrics,
        "stake":   _parse_stakeholders,
        "obj":     _parse_objectives,
    }

    for key, filename, missing_code, extras_field in pairs:
        path = sidecar_dir / filename
        if path.is_file():
            presence[key] = True
            parsed = parsers[key](path)
            if key == "problem" and not parsed:
                sink.add("W201", "problem-statement.md present but empty",
                         path=f"docs/c1-discovery/{filename}")
            elif key != "problem" and not parsed:
                sink.add("W205", f"{filename} present but no rows parsed",
                         path=f"docs/c1-discovery/{filename}")
            extras[extras_field] = parsed
        else:
            sink.add(missing_code, f"{filename} missing",
                     path=f"docs/c1-discovery/{filename}")

    return presence, extras


def _detect_source_format(project_root: Path) -> str:
    """Auto-detect the ticket-tracking format for this project (ADR-051).

    Priority order:
      1. docs/c1-discovery/backlog.md  → "backlog"   (ADR-040 canonical)
      2. todos.csv at project root     → "csv"        (legacy CSV tracker)
      3. nothing found                 → "unknown"    (caller raises E501)
    """
    if (project_root / "docs" / "c1-discovery" / "backlog.md").is_file():
        return "backlog"
    if (project_root / "todos.csv").is_file():
        return "csv"
    return "unknown"


def run_pipeline(args: argparse.Namespace) -> dict[str, Any]:
    """Execute the full parse pipeline and return the envelope dict.

    ADR-051: auto-detects source format (backlog.md / todos.csv) so the
    skill works on any project ⟦ user_name ⟧ invokes it on without format restrictions.
    """
    project_root = Path(args.project_root).resolve(strict=True)

    source_format = _detect_source_format(project_root)

    if source_format == "csv":
        # Route to CSV adapter (ADR-051). Imports deferred to avoid stdlib
        # path confusion when running from a non-skill cwd.
        logger.info("auto-detected source format: csv (todos.csv) — routing to csv_adapter")
        try:
            from _lib.csv_adapter import parse_csv  # noqa: PLC0415
        except ImportError:
            sys.exit(50)  # E501 unrecognised format / adapter missing
        csv_path = project_root / "todos.csv"
        return parse_csv(csv_path, project_root)

    if source_format == "unknown":
        # Neither backlog.md nor todos.csv — fail loudly with E501.
        logger.error(
            "E501 unrecognised source format in %s: "
            "neither docs/c1-discovery/backlog.md nor todos.csv found. "
            "Create one of those files or pass a supported --source-format.",
            project_root,
        )
        sys.exit(50)

    # ── backlog.md path (original ADR-040 flow) ────────────────────────────
    backlog_path = project_root / "docs" / "c1-discovery" / "backlog.md"
    if not backlog_path.is_file():
        raise E101BacklogMissing(f"backlog.md not found at {backlog_path}")
    if backlog_path.stat().st_size == 0:
        raise E102BacklogEncoding(f"backlog.md empty at {backlog_path}")

    text = _read_text(backlog_path)

    if re.match(r"^\s*---\s*\n", text) and not args.accept_yaml_frontmatter:
        raise E103YamlFrontmatter(
            "backlog.md begins with YAML frontmatter; pass --accept-yaml-frontmatter to opt in"
        )

    sink = WarningSink()
    name_from_h1, cards = _parse_backlog(text, sink)
    presence, extras = _ingest_sidecars(project_root, sink)

    _apply_status_overlay(cards, project_root / ".dashboard" / "status.json", sink)
    _validate_dependencies(cards, sink)
    _detect_cycles(cards, sink)

    reviews = _scan_reviews(project_root / "docs" / "architecture" / "reviews",
                            project_root, sink)

    return _build_envelope(
        project_root=project_root,
        project_name=name_from_h1 or project_root.name,
        cards=cards,
        extras=extras,
        reviews=reviews,
        presence=presence,
        warnings_list=sink.as_list(),
    )


# --------------------------------------------------------------------------- #
# CLI                                                                         #
# --------------------------------------------------------------------------- #

def _build_argparser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="parser-core",
        description="ARCA dashboard-build parser core (T11). Emits intermediate JSON or hydrated HTML.",
    )
    parser.add_argument("--project-root", required=True,
                        help="Absolute path to the project root containing docs/c1-discovery/backlog.md")
    parser.add_argument("--mode", choices=("json", "html"), default="json",
                        help="Output JSON envelope (default) or hydrated HTML.")
    parser.add_argument("--cycle", type=int, default=None,
                        help="Cycle number 1..14 (informational; parser does not branch on it).")
    parser.add_argument("--accept-yaml-frontmatter", action="store_true",
                        help="Opt in to mixed Markdown-table + YAML frontmatter format.")
    parser.add_argument("--self-check", action="store_true",
                        help="Re-parse emitted JSON via json.loads as a sanity gate before exit.")
    parser.add_argument("--template",
                        help="Absolute path to templates/dashboard/index.html (required for --mode html).")
    return parser


def _configure_logging() -> None:
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)sZ [%(name)s] [%(levelname)s] %(message)s",
        datefmt="%Y-%m-%dT%H:%M:%S",
        stream=sys.stderr,
    )
    logging.Formatter.converter = lambda *_args: datetime.now(timezone.utc).timetuple()


def _emit_json(envelope: dict[str, Any], self_check: bool) -> None:
    """Serialise envelope to stdout; optionally round-trip through json.loads."""
    payload = json.dumps(envelope, ensure_ascii=False, indent=2, sort_keys=False)
    if self_check:
        try:
            json.loads(payload)
        except json.JSONDecodeError as exc:
            raise E901SelfCheck(f"emitted JSON is not parseable: {exc}") from exc
    sys.stdout.write(payload)
    sys.stdout.write("\n")


def _emit_html(envelope: dict[str, Any], template_path: Path) -> None:
    """Hydrate the template and write the result to stdout."""
    if not template_path.is_file():
        raise E401TemplateMissing(f"template not found at {template_path}")
    rendered = hydrator.hydrate(template_path, envelope)
    sys.stdout.write(rendered)


def main(argv: list[str] | None = None) -> int:
    _configure_logging()
    parser = _build_argparser()
    args = parser.parse_args(argv)

    try:
        envelope = run_pipeline(args)
        if args.mode == "json":
            _emit_json(envelope, args.self_check)
        else:
            if not args.template:
                logger.error("--template is required when --mode html")
                return 100
            _emit_html(envelope, Path(args.template))
        return 0
    except ParserError as exc:
        logger.error("[%s] %s", exc.code, exc)
        return exc.exit_code
    except FileNotFoundError as exc:
        logger.error("[E101] %s", exc)
        return 10


if __name__ == "__main__":
    raise SystemExit(main())
