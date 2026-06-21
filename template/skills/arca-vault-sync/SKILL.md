---
name: arca-vault-sync
description: "Snapshots the ARCA-relevant subset of the Obsidian vault into the private repo your-vault-repo and commits any drift. One-way mirror, vault → repo. Use when the user says 'sync vault', 'backup vault', '/arca-vault-sync', or whenever ARCA artifacts in Obsidian need versioning. The repo is private on GitHub by design — Status.md blocks leak project structure. Selection policy is fixed: Projects/ARCA/** + Projects/<proj>/Status.md + Projects/<proj>/CICLO-*/** + Projects/<proj>/diario/** + Templates/ARCA/** + Engram-Digests/**. Everything else (code repos, binaries, personal data under Mylife/, Work/Roadmap/) stays in the vault and never reaches the repo."
allowed-tools: [Bash]
---

# arca-vault-sync

Tier-3 Obsidian integration. Versions the ARCA artifacts that the vault
accumulates without dragging the rest of ⟦ user_name ⟧'s vault into git.

## Why a separate repo

The vault root weighs 7+ GB and contains personal medical data plus
embedded code repos. ADR-010 details the rationale. This skill is the
operator that keeps the snapshot fresh.

## Trigger phrases

- "sync vault"
- "backup vault notes"
- "/arca-vault-sync"
- After a session that produced new Status.md / CICLO-N artifacts and
  the user wants them versioned.

## Inputs

- `--push`     also push to origin/main after committing.
- `--dry-run`  preview what would change.

## Procedure

1. Verify `your-vault-repo` repo exists at `~/Desktop/⟦ host_alias ⟧/your-vault-repo` (moved OUT of the vault 2026-06-11 — living inside the vault made Obsidian index mirrored notes as duplicates).
2. Wipe `Projects/`, `Templates/`, `Engram-Digests/` inside the repo
   (not `.git`, not README, not `.gitignore`).
3. Apply the selection policy via the bundled Python walker:
   - Projects/ARCA: full tree
   - Other projects: only `Status.md` (top-level), `CICLO-*/**` and `diario/**`
   - Templates/ARCA: full tree
   - Engram-Digests: full tree
   - Skip embedded code repos (any dir with a `.git` child).
   - Skip files > 2MB and any non-md file.
4. `git add` + commit if dirty (`vault: auto-sync <ts>`).
5. If `--push`: `git push origin main`.

## Bash recipe

```bash
bash $HOME/Desktop/⟦ host_alias ⟧/.claude/scripts/arca-vault-sync.sh --push
```

## When NOT to trigger

- The user is editing a vault note right now — wait for the edit to
  finish (Obsidian saves async; the snapshot would miss it).
- Engram is offline AND no new vault notes exist — nothing to sync.
