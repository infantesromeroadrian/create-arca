---
name: obsidian-cycle-close
description: Closes a Pipeline ML cycle by materializing the 4 mandatory Obsidian notes — Status / Decisions / Blockers / Retrospective — under <vault>/Projects/<project>/CICLO-<N>/. Use when the user signals "cerrar ciclo C<N>", "ciclo cerrado", "/cycle-close <N>", or any phrasing that ends a pipeline cycle and ARCA needs to persist the artifacts CLAUDE.md mandates. Reads templates from <vault>/Templates/ARCA/ and substitutes minimal frontmatter (project, cycle, date) inline. Never overwrites existing files; aborts loudly if the cycle dir already exists, so accidental re-closes do not erase prior decisions.
allowed-tools: [Read, Write, Bash, Glob]
---

# obsidian-cycle-close

Materializes the four Obsidian notes that CLAUDE.md mandates for every
pipeline cycle close:

- `Status.md` — what landed, what is open, where to pick up.
- `Decisions.md` — architectural choices + trade-offs + ADR refs.
- `Blockers.md` — active blockers, those resolved, ownerless risks.
- `Retrospective.md` — worked / didn't / surprised, metrics, next steps.

## Trigger phrases

- "cerrar ciclo C<N>"
- "ciclo cerrado"
- "/obsidian-cycle-close <N>"
- "obsidian close cycle <N>"
- Any sentence where the user explicitly ends a pipeline cycle and
  expects the closing artifacts to land in the vault.

## Inputs

- Cycle number (`<N>`) — 1..14 per `rules/pipeline-ml.md`.
- Project name — defaults to basename of `$PWD`; override with the
  current working project if you are in a worktree subdir.
- Vault path — `${ARCA_VAULT:-$HOME/Desktop/⟦ host_alias ⟧}`.

## Procedure

1. **Locate templates**: read all four files from
   `${VAULT}/Templates/ARCA/{Status,Decisions,Blockers,Retrospective}.md`.
   If any is missing, abort with a clear message — do not silently
   degrade.

2. **Build the destination**: `${VAULT}/Projects/<project>/CICLO-<N>/`.
   If this dir already has any of the four target files, abort.
   Re-closing a cycle should be an explicit human decision, not a
   silent overwrite.

3. **Substitute Templater variables minimally**: replace
   `<% tp.file.folder(false) %>` with the project name,
   `<% tp.date.now("YYYY-MM-DD") %>` with today,
   `<% tp.user.cycle || "C?" %>` with `C<N>`. The other Templater
   tokens stay literal — Obsidian Templater will resolve them on
   first open.

4. **Write the four files**.

5. **Print the four absolute paths back** so the user can open them
   from the terminal or click them in Obsidian.

## Bash recipe (canonical)

```bash
N="$1"
PROJECT="$(basename "$PWD")"
VAULT="${ARCA_VAULT:-$HOME/Desktop/⟦ host_alias ⟧}"
TARGET="${VAULT}/Projects/${PROJECT}/CICLO-${N}"

[[ -z "$N" ]] && { echo "usage: cycle <N>"; exit 2; }
mkdir -p "$TARGET" || exit 1
TODAY="$(date +%Y-%m-%d)"

for tpl in Status Decisions Blockers Retrospective; do
    src="${VAULT}/Templates/ARCA/${tpl}.md"
    dst="${TARGET}/${tpl}.md"
    [[ -f "$dst" ]] && { echo "ABORT: $dst exists"; exit 1; }
    sed \
        -e "s|<% tp.file.folder(false) %>|${PROJECT}|g" \
        -e "s|<% tp.date.now(\"YYYY-MM-DD\") %>|${TODAY}|g" \
        -e "s|<% tp.user.cycle \\|\\| \"C?\" %>|C${N}|g" \
        "$src" > "$dst"
    echo "wrote $dst"
done
```

## When NOT to trigger

- The user is just *reflecting* on a cycle, not closing it.
- The pipeline cycle has not yet passed its blocking gate (the
  agent-owner of that cycle must sign off first; see
  `rules/pipeline-ml.md`).
- Already-closed cycle: the dir exists. Tell the user to remove
  manually if a re-close is intentional.

## Dashboard regen (ADR-052 + ADR-053, 2026-05-14)

Per ADR-052 (supersedes ADR-049 same-day): the project panel is **Markdown Kanban native** in Obsidian, NOT HTML standalone. Per ADR-053: a generic script with project-detect auto-regenerates the Kanban whenever `todos.csv` or `backlog.md` changes.

Closing a cycle is a TWO-step operation. The Obsidian notes above are step 1; the Markdown Kanban refresh is step 2.

Step 2 procedure:

```bash
# (a) Operator (or @project-planner) updates the source of truth
#     (docs/c1-discovery/backlog.md ADR-040, or todos.csv for legacy
#     projects like ⟦ org_name ⟧-<Client>) reflecting cards moved during C<N>.

# (b) Regenerate the L2 Kanban for this project. Path-aware: any project.
python3 "${HOME}/Library/Mobile Documents/com~apple~CloudDocs/projects/scripts/regenerate-kanban-hierarchy.py" \
    --mode l2 \
    --source "${PROJECT_ROOT}/todos.csv" \
    --target "${VAULT}/Projects/${CATEGORIA}/${PROJECT_NAME}/Dashboard-${PROJECT_NAME}.md" \
    --name "${PROJECT_NAME}"

# (c) Refresh the L0 aggregator (scans all Dashboard-*.md outputs).
python3 "${HOME}/Library/Mobile Documents/com~apple~CloudDocs/projects/scripts/regenerate-kanban-hierarchy.py" \
    --mode l0 \
    --vault-projects "${VAULT}/Projects"
```

**Auto-regen (per ADR-053)**: when the hook `dashboard-auto-regen.sh` is wired (pending implementation), `PostToolUse:Edit/Write` on `**/todos.csv` or `**/backlog.md` invokes the script automatically with detected project root. The skill chain above is the manual fallback.

**No HTML, no CDN, no iframe**: the empirical test on 2026-05-14 18:50 demonstrated Obsidian CSP blocks both. The `/dashboard-build` skill (ADR-049) is deprecated. The hook `cycle-dashboard-enforcer.sh` is deactivated.

Universal scope (per ADR-053): applies to any project regardless of creation date or source format. Pre-ADR-052 projects do NOT have a separate flow; everything converges on Markdown Kanban.

## Cross-refs

- `rules/pipeline-ml.md` — the 14 cycles authoritative spec.
- `~/.claude/CLAUDE.md` — the mandate ("Obsidian al cerrar cada ciclo" + ADR-052 reflex).
- ADR-052 — Markdown Kanban native > HTML standalone (supersedes ADR-049 + 050 + 051).
- ADR-053 — generic script + auto-regen hook + L0 aggregator (universal scope).
- `~/Library/Mobile Documents/com~apple~CloudDocs/projects/scripts/regenerate-kanban-hierarchy.py` — the canonical regenerator.
- `skills/dashboard-build/SKILL.md` — DEPRECATED, kept for trail.
- `hooks/cycle-dashboard-enforcer.sh` — DEACTIVATED (never wired in settings.json; ADR-052 §Decision §4 ratifies the deactivation).
