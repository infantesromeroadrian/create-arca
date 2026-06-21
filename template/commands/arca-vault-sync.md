---
description: Mirror the ARCA-relevant subset of the Obsidian vault into the private repo your-vault-repo and commit any drift. Usage `/arca-vault-sync [--push] [--dry-run]`.
---

Run `scripts/arca-vault-sync.sh` with the user's flags. By default
the sync commits locally only; pass `--push` to also push to origin.
Print the resulting git log line.
