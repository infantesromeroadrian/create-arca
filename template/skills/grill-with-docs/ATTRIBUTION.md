# Attribution

**Source:** https://github.com/mattpocock/skills (skills/grill-with-docs/)
**Author:** Matt Pocock (Total TypeScript creator)
**License:** MIT
**Installation method:** `npx skills@latest add mattpocock/skills -s grill-with-docs --global -y --copy`
**Snapshot date in ARCA:** 2026-05-04

## License terms

MIT — copy + redistribute permitted with attribution. ARCA preserves the SKILL.md, ADR-FORMAT.md, and CONTEXT-FORMAT.md verbatim from the upstream snapshot.

## Why this skill is in ARCA

Adopted on 2026-05-04 to add adversarial stress-testing to ARCA's C1 Discovery and C4 Design cycles. The skill challenges proposals against the existing domain model + sharpens terminology + updates documentation (CONTEXT.md, ADRs) inline as decisions crystallise. Complements `@architect-ai` workflow before signing an ADR — second-opinion adversarial review without invoking another agent.

Particularly useful in:
- **C1 Discovery**: stress-test ML Problem Statement against existing pipeline conventions
- **C4 Design**: challenge ADR drafts against prior ADRs (avoids architectural drift)
- **Pre-deploy review**: terminology consistency check before C10

## ADR + CONTEXT format reference

The skill includes ADR-FORMAT.md and CONTEXT-FORMAT.md reference files that establish terminology conventions. These formats are NOT a replacement for ARCA's existing ADR template (Nygard-lite per docs/adr/) — they are an additional perspective that the skill applies during audits. ARCA's ADR template remains canonical for new ADR creation; this skill audits compliance + suggests refinements.

Updates: re-run the install command above, then `cp -r ~/.claude/skills/grill-with-docs/* skills/grill-with-docs/`.
