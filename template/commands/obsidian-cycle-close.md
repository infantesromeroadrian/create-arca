---
description: Materialize the 4 mandatory Obsidian notes (Status / Decisions / Blockers / Retrospective) for a closing pipeline cycle. Usage `/obsidian-cycle-close <N>`.
---

Run the canonical bash recipe from `skills/obsidian-cycle-close/SKILL.md`
with the cycle number provided by the user (e.g. `/obsidian-cycle-close 4`
closes C4 / Design).

Confirm:

1. The project name is correct (basename of `$PWD`).
2. The cycle's blocking gate has actually passed (per `rules/pipeline-ml.md`).
3. The destination dir does not already contain the four files (no
   accidental overwrite of prior decisions).

After writing, list the four absolute paths and offer to open them.
