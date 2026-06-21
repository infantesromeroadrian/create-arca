---
description: Show ARCA pipeline state — current phase, gates signed and pending, history, expected artifacts. Read-only.
---

First source `hooks/lib/phase-state.sh` and call `phase_state_is_dormant`. If it returns 0 (true), the current cwd is a meta-ecosystem repo per ADR-037 (.claude, your-snapshots-repo, your-vault-repo, etc.). In that case output exactly:

```
Pipeline state: DORMANT (this is a meta-ecosystem repo per ADR-037).
No active phase. To start a real ML pipeline, /ml-new in a new project directory.
```

…and exit. Do NOT touch the state file, do NOT report a fake C1.

Otherwise, read `~/.claude/state/arca-pipeline-state.json` and `hooks/lib/phase-gates.json`. Render a compact dashboard of the active project's phase progress:

1. Active project + current phase + when it opened.
2. Gates signed in current phase (from state) vs gates required (from canonical map).
3. Blocking gates still missing — the ones that prevent advance.
4. Artifacts expected for current phase + which exist on disk.
5. Brief history: previous phases with their close timestamps.
6. Audit log tail (last 5 entries from `~/.claude/state/phase-gate-audit.log`).

Output is concise, plain text, no decoration. The file is the source of truth — never invent state.
