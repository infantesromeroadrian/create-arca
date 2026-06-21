---
description: Close current ARCA phase with full gate verification and advance to the next. Usage `/close-phase <current-phase>` (e.g. `/close-phase C1`). Refuses to advance if blocking gates are unsigned.
---

Validate that ALL blocking gates of the current phase are signed in `~/.claude/state/arca-pipeline-state.json`. If any are missing, refuse the close and list them. If all pass:

1. Verify required artifacts (per `hooks/lib/phase-gates.json`) exist on disk.
2. Source `hooks/lib/phase-state.sh`.
3. Compute next phase id (C(n) -> C(n+1)).
4. Call `phase_state_advance "<next>"` to record close + open transition.
5. Write a closing entry to Engram (`type: phase_close`) with project name, gates passed, artifacts shipped.
6. Show new state via `/phase-status`.

If the user passes a phase id that does NOT match `current_phase`, abort with a clear error — never silently rewrite state. For intentional retreat use `/phase-rewind <N>` instead.
