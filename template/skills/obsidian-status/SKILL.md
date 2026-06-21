---
name: obsidian-status
description: Manually rewrites <vault>/Projects/<project>/Status.md with the current session state. Use when the user wants to checkpoint progress mid-session, force a status snapshot before compaction, or fix a Status.md that drifted from reality. The Stop hook (obsidian-session-close.sh) does this automatically at session end; this skill is the manual "do it now" version. Never appends a duplicate identical block — checks against the current branch+sha before writing.
allowed-tools: [Read, Write, Bash]
---

# obsidian-status

Manual companion to the automatic `Stop`-event hook
(`hooks/obsidian-session-close.sh`). Rewrites the Status.md at the
project's vault folder with a fresh session block.

## Trigger phrases

- "actualiza el status"
- "checkpoint en obsidian"
- "/obsidian-status"
- "snapshot status"
- The user wants Status.md updated NOW without waiting for session
  end.

## Inputs

- Project name — defaults to basename of `$PWD`.
- Optional summary text — if the user dictates the body, use it
  verbatim. Otherwise build it from git log + open todos.

## Procedure

Same shape as the Stop hook: prepend a `## Session <ts>` block right
after the auto-appended marker. Read first; do not duplicate an
identical block (same branch+sha+timestamp-minute).

## Bash recipe

```bash
PROJECT="$(basename "$PWD")"
VAULT="${ARCA_VAULT:-$HOME/Desktop/⟦ host_alias ⟧}"
F="${VAULT}/Projects/${PROJECT}/Status.md"

# Reuse the hook to keep behavior aligned.
bash "$HOME/.claude/hooks/obsidian-session-close.sh" </dev/null
echo "wrote ${F}"
```

## When NOT to trigger

- A Stop event already fired in the last 60 seconds — the file is
  fresh.
- The project is a worktree feature branch with throwaway state — let
  the parent repo's Stop event own the truth.
