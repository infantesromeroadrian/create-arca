---
description: Force pipeline state back to phase N (audit-logged). Use when scope changes mid-pipeline and earlier gates need to re-fire. Usage `/phase-rewind <C-N>`.
---

Destructive operation. Requires explicit user confirmation in chat before execution.

1. Show what is being rewound: current phase + target phase + gates that will be discarded.
2. Wait for "yes" / "confirmed" in chat.
3. On confirmation: rewrite `arca-pipeline-state.json`:
   - `current_phase` -> target
   - `gates_signed_current_phase` -> []
   - Append rewind event to `phase_history` with `rewound_from`, `rewound_to`, `reason` (ask user).
4. Append entry to `~/.claude/state/phase-rewind-audit.log` with timestamp + actor (always ⟦ user_name ⟧; not invocable by sub-agents).
5. Best-effort Engram save (`type: phase_rewind`).
6. Show new state via `/phase-status`.

Refuse to rewind to a phase >= current. Refuse to rewind without `--reason "<text>"` argument so the audit trail captures intent.
