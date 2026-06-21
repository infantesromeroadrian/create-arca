# prompt-master — Attribution

## Source

- **Author**: Nidhin Joseph Nelson ([@nidhinjs](https://github.com/nidhinjs))
- **Repo**: https://github.com/nidhinjs/prompt-master
- **License**: MIT (Copyright (c) 2026 Nidhin Joseph Nelson)
- **Version cherry-picked**: 1.6.0
- **Stars at time of adoption**: 7.1k
- **Adopted on**: 2026-05-04

## Files vendored

- `SKILL.md` — frontmatter + body (verbatim)
- `LICENSE` — MIT (verbatim, required by license)
- `README.md` — install + usage docs (verbatim)
- `references/patterns.md` — supporting reference
- `references/templates.md` — supporting reference

No modifications to the upstream content. Re-install on a new machine:

```bash
git clone --depth 1 https://github.com/nidhinjs/prompt-master.git /tmp/prompt-master-clone
cp /tmp/prompt-master-clone/SKILL.md /tmp/prompt-master-clone/LICENSE \
   /tmp/prompt-master-clone/README.md ~/.claude/skills/prompt-master/
cp /tmp/prompt-master-clone/references/*.md ~/.claude/skills/prompt-master/references/
```

Or upload as ZIP via claude.ai sidebar (Customize -> Skills -> Upload).

## ARCA-specific reason for adoption

`prompt-master` fills a gap in ARCA's catalog: producing **prompts to paste into external AI tools** (Midjourney, Cursor, ChatGPT, Gemini, Sora, etc.). Distinct from ARCA's `@prompt-engineer` agent, which audits and optimizes the prompts that DEFINE ARCA's own agents (system-level frontmatter + body of `agents/*.md`).

Zero overlap:

| Capability | Scope |
|---|---|
| `@prompt-engineer` (ARCA agent, internal) | Audits/optimizes the prompts of ARCA's 49 agents |
| `prompt-master` (skill, external) | Produces single-shot prompts for 20+ external AI tools |

Use cases for ⟦ user_name ⟧:
- Generating Midjourney / SD / DALL-E prompts during landing-page work (already validated 2026-05-04 with the flipbook landing aesthetic upgrade).
- Cross-tool prompt comparisons when evaluating Cursor/Windsurf/Claude Code.
- Quick prompts for ChatGPT/Gemini when ⟦ user_name ⟧ wants a second opinion outside the Claude ecosystem.

## Cross-references in ARCA

- `agents/prompt-engineer.md` — added "Skill complementaria" section pointing to `prompt-master` for external-tool prompt generation (NOT for internal ARCA agent prompts; that's still `@prompt-engineer`'s scope).
- This file documents the source + license + reason. Source URL preserved per MIT requirement and ARCA's expert-curated cherry-pick pattern (see Emil Kowalski 2026-05-04, Kyle Zantos 2026-05-04, Matt Pocock 2026-05-04).

## Name coexistence note

`prompt-master` (skill, this folder, auto-routed by `@skill-router` when description matches) does NOT collide with `@prompt-engineer` (ARCA agent in `agents/prompt-engineer.md`). Different namespaces (skill vs agent) and different scopes (external vs internal). They can coexist and complement each other.

## Pattern provenance

Fourth in the 2026-05-04 series of expert-curated cherry-picks:
1. `emil-design-eng` (Emil Kowalski)
2. `design-motion-principles` (Kyle Zantos)
3. `diagnose` / `grill-with-docs` / `to-prd` (Matt Pocock)
4. `prompt-master` (Nidhin Joseph Nelson) ← this one

Each addition selective per evidence-based audit, not catalog adoption.
