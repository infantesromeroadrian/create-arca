---
description: Manually checkpoint the current session into Obsidian's `<vault>/Projects/<project>/Status.md`. Usage `/obsidian-status`.
---

Trigger the manual variant of the Stop-event hook so the user can
snapshot progress without waiting for session close. Reuses
`hooks/obsidian-session-close.sh` to stay aligned with the automatic
path.

After writing, surface the absolute path of the Status.md.
