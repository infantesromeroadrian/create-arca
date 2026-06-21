# Attribution

**Source:** https://github.com/mattpocock/skills (skills/to-prd/)
**Author:** Matt Pocock (Total TypeScript creator)
**License:** MIT
**Installation method:** `npx skills@latest add mattpocock/skills -s to-prd --global -y --copy`
**Snapshot date in ARCA:** 2026-05-04

## License terms

MIT — copy + redistribute permitted with attribution. ARCA preserves the SKILL.md verbatim from the upstream snapshot.

## Why this skill is in ARCA

Adopted on 2026-05-04 to formalize the "this conversation has crystallised into a spec, capture it" pattern. When a discussion with ARCA derives into an implicit Product Requirements Document, this skill turns the conversation context into a structured PRD published to the project issue tracker (GitHub Issues by default). Complements `@project-planner` C1 Discovery workflow:

- **`@project-planner`** elicits requirements via 4-level (Business/User/System/ML) and produces ML Problem Statement
- **`to-prd`** captures emergent specs that arise mid-conversation outside the formal C1 entry — common when ⟦ user_name ⟧ iterates an idea aloud and lands on something concrete

Without `to-prd`, ad-hoc decisions stay in the conversation history (or Engram if explicitly saved) but never become trackeable backlog. With it, they become GitHub issues with full context.

## Configuration

The skill expects a configured issue tracker via `setup-matt-pocock-skills` (NOT installed in ARCA — ARCA already has GitHub CLI authenticated for `gh issue create`). When invoked, the skill should default to the current `git remote origin` repo. ⟦ user_name ⟧ may need to manually configure target repo on first invocation.

Updates: re-run the install command above, then `cp -r ~/.claude/skills/to-prd/* skills/to-prd/`.
