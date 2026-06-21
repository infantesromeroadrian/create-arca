"""Exit-coded fatal exceptions for the dashboard-build parser core.

Each subclass pins (exit_code, code) to mirror the parser-contract.md catalogue.
The CLI maps caught instances to ``sys.exit(exc.exit_code)`` and logs ``exc.code``
plus the message via the structured logger.
"""

from __future__ import annotations


class ParserError(Exception):
    """Base parser-core fatal error. Subclasses pin (exit_code, code)."""

    exit_code: int = 1
    code: str = "E000"


class E101BacklogMissing(ParserError):
    exit_code, code = 10, "E101"


class E102BacklogEncoding(ParserError):
    exit_code, code = 11, "E102"


class E103YamlFrontmatter(ParserError):
    exit_code, code = 12, "E103"


class E104NoMustHeader(ParserError):
    exit_code, code = 13, "E104"


class E201TableHeader(ParserError):
    exit_code, code = 20, "E201"


class E202DuplicateId(ParserError):
    exit_code, code = 21, "E202"


class E203UnresolvedDep(ParserError):
    exit_code, code = 22, "E203"


class E204BadId(ParserError):
    exit_code, code = 23, "E204"


class E205BadCycle(ParserError):
    exit_code, code = 24, "E205"


class E206BadType(ParserError):
    exit_code, code = 25, "E206"


class E207BadImpact(ParserError):
    exit_code, code = 26, "E207"


class E208BadConfidence(ParserError):
    exit_code, code = 27, "E208"


class E209BadReachEffort(ParserError):
    exit_code, code = 28, "E209"


class E210BadStoryPoints(ParserError):
    exit_code, code = 29, "E210"


class E301WontHeader(ParserError):
    exit_code, code = 30, "E301"


class E401TemplateMissing(ParserError):
    """Repo-level artefact missing (schema.json or template/index.html)."""

    exit_code, code = 40, "E401"


class E402OutputUnwritable(ParserError):
    exit_code, code = 41, "E402"


class E403StatusOverlayMalformed(ParserError):
    exit_code, code = 42, "E403"


class E901SelfCheck(ParserError):
    exit_code, code = 90, "E901"


class CardDropped(Exception):
    """Control-flow signal: card discarded due to a W4xx-class warning."""

    def __init__(self, card_id: str) -> None:
        super().__init__(card_id)
        self.card_id = card_id
