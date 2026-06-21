---
description: Materialize last 7 days (or --days N) of Engram entries into <vault>/Engram-Digests/<YYYY-MM-DD>.md for Obsidian Dataview indexing. Usage `/engram-to-obsidian [--days N] [--limit N] [--project NAME]`.
---

Run `scripts/engram-to-obsidian.sh` with the user-provided flags (or
defaults). Print the absolute path of the resulting digest. Do NOT
fabricate Engram content if the CLI is missing — fail loudly.
