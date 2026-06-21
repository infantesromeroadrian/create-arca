---
name: engram-to-obsidian
description: "Materializes the most recent Engram entries for the current project as a Markdown digest under <vault>/Engram-Digests/<YYYY-MM-DD>.md so the Obsidian Dashboard Dataview queries can index them. Use when the user asks to 'sync engram to obsidian', 'generate engram digest', 'refresh engram notes', or any phrasing that exports persistent memory into the vault for browsing/search. Stacking multiple refreshes in a single day is supported (each one appends a timestamped block). The digest carries frontmatter 'type: engram-digest' so the Dashboard query picks it up automatically."
allowed-tools: [Bash, Read]
---

# engram-to-obsidian

Tier-2 Obsidian integration. Bridges Engram (persistent memory MCP)
into the Obsidian vault as plain Markdown so Dataview queries on the
Dashboard can index, sort, and link to the digests.

## Trigger phrases

- "sync engram to obsidian"
- "engram digest"
- "refresh engram notes"
- "/engram-to-obsidian"
- The user wants to materialize the last week (or N days) of Engram
  activity into the vault.

## Inputs

- `--days N`     — window size in days (default 7)
- `--limit N`    — max entries (default 50)
- `--project X`  — project filter; defaults to basename of `$PWD`.

## Procedure

1. Verify `engram` CLI is on PATH. Abort if missing — the user must
   install Engram first.
2. Resolve target file: `<vault>/Engram-Digests/<YYYY-MM-DD>.md`.
3. If the file already exists, append a `## Refresh <ts>` block and
   the new entries. Otherwise create it with the canonical frontmatter
   (`type: engram-digest`, `project`, `window_days`, `entries_count`).
4. Pull entries via `engram timeline --project <P> --limit <L>`. If
   the project filter returns nothing, fall back to global timeline.
5. Update `entries_count` in frontmatter on first write of the day.
6. Print the absolute path of the digest.

## Bash recipe

```bash
bash $HOME/Desktop/⟦ host_alias ⟧/.claude/scripts/engram-to-obsidian.sh \
    --days 7 --limit 50
```

## When NOT to trigger

- The user is asking to *read* Engram, not to mirror it.
- Engram is unreachable (CLI absent, MCP down) — fail loudly, do not
  fabricate digest content.
- The user wants real-time queries — that is `mem_search`, not a
  digest.
