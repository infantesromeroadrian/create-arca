---
description: Refresh Claude's native memory directory by pulling top-K Engram entries for the current project via engram-rehydrate skill.
---

Refresh Claude's native memory directory by pulling top-K Engram entries for the current project.

Invokes the `engram-rehydrate` skill. Materializes semantic long-term memory (Engram) into the Memory tool's filesystem format at `~/.claude/memory/<project-slug>/`.

Use at the start of a new session on a known project, or when the session_start hook reports memory/ is stale.

**Idempotent:** re-invoking within 24h is a no-op (skill checks README.md mtime). Force refresh by deleting the directory first.

## What it does

1. Compute project slug from git remote or cwd.
2. Query Engram MCP (`mem_context`, `mem_search`, `mem_timeline`).
3. Dedupe, pick top K (default 10).
4. Write each as `<NNN>-<slug>.md` with `source: engram` frontmatter.
5. Regenerate `README.md` index.

## Kill switch

Create `~/.claude/memory-rehydrate-off` to disable.

## See also

- `skills/engram-rehydrate/SKILL.md` — full protocol and config schema.
- `hooks/session_start.sh` — nudges when memory/ is stale.
