---
name: dashboard-build
status: deprecated (superseded by ADR-052, 2026-05-14 — Markdown Kanban native > HTML standalone)
description: "DEPRECATED skill. Kept on disk as historical reference per ADR-052 §Decision §2. Use `regenerate-kanban-hierarchy.py` (per ADR-053) to generate the Markdown Kanban dashboard in Obsidian instead. Historical scope: built per-project single-pane HTML dashboard from <project>/docs/c1-discovery/backlog.md or todos.csv into <project>/dashboard/index.html. Failed empirical test 2026-05-14 18:50 — iframe `file://` blocked by Obsidian CSP + Tailwind CDN blocked; HTML standalone could not embed inside the vault."
when_to_use: do NOT invoke — use Markdown Kanban regen (ADR-052/053). This SKILL.md exists only for trail; do not auto-invoke under any reflex.
argument-hint: "(deprecated — legacy: --project-root <abs-path> --cycle <N> [--accept-yaml-frontmatter] [--self-check])"
disable-model-invocation: true
user-invocable: false
allowed-tools: Bash
model: sonnet
effort: medium
---

# /dashboard-build — DEPRECATED (superseded by ADR-052/053)

**This skill is deprecated as of 2026-05-14 per ADR-052.** The HTML standalone approach cannot embed inside Obsidian (CSP blocks `file://` iframe + Tailwind CDN). Markdown Kanban native is now the canonical project dashboard.

**Use instead**: `~/Library/Mobile Documents/com~apple~CloudDocs/projects/scripts/regenerate-kanban-hierarchy.py` (made universal by ADR-053 with `--mode l2|l0` args).

**Why kept on disk**: ADR-052 §Decision §2 mandates preserving this skill for historical trail. Do NOT delete. Do NOT invoke. Do NOT regenerate dashboard outputs from it. `disable-model-invocation: true` + `user-invocable: false` in frontmatter prevent accidental routing.

---

## Historical scope (pre-ADR-052)

Closes ADR-049 by producing the two mandatory cycle-close artefacts:

1. `<project>/dashboard/index.html` — single-pane HTML (Tailwind CDN + vanilla JS, three sections).
2. `<project>/docs/architecture/reviews/architect-review-C<N>.md` — continuous review, emitted via ad-hoc invocation of `@architect-ai` from inside this skill (Option B in ADR-049 — agent prompt is not modified).

## When to use

- `@project-planner` closes a cycle and the hook `cycle-dashboard-enforcer.sh` blocks advance to the next cycle.
- The operator edits `backlog.md` and wants the board to reflect the change before the next stand-up.
- An architect review file is missing for the just-closed cycle.
- A speech / demo is upcoming and the cumulative speech scroll must include the latest cycle.

## When NOT to use

- Pre-ADR-049 project that opted out of dashboard adoption (legacy projects per ADR-049 §Scope).
- Backlog file does not yet exist (run `/backlog-init` first).
- Cycle number outside `1..14` — the cycle range is bounded by the ARCA Pipeline v4.0.

## How it works

1. **Argument + path sanitisation** — `--project-root` must be an existing directory; `realpath` must resolve within the repo workspace; `..` segments and out-of-repo symlinks reject with E1xx. `--cycle` must be `1..14`.
2. **Parse backlog** — read `<project-root>/docs/c1-discovery/backlog.md` per `docs/specs/dashboard-build/parser-contract.md`. YAML frontmatter rejected unless `--accept-yaml-frontmatter` flag or `DASHBOARD_BUILD_ACCEPT_YAML=1` env opts in.
3. **Read sidecars** — `problem-statement.md`, `success-metrics.md`, `stakeholders.md`, `objectives.md`. Missing files emit W2xx warnings, non-fatal.
4. **Scan architecture reviews** — glob `docs/architecture/reviews/architect-review-C[0-9]*.md`, derive `cycle` from filename, truncate `summary` to 200 chars.
5. **Build intermediate JSON** — conforming to `docs/specs/dashboard-build/schema.json`.
6. **Self-check** — `jq empty` on the emitted JSON; failure is E901 (parser bug).
7. **Ad-hoc architect invocation** — if `architect-review-C<N>.md` is missing, invoke `@architect-ai` from this skill with a cycle-scoped prompt. If the Claude Code Agent SDK is not reachable from bash (skill runs outside an interactive session), emit warning W301-mode and instruct the operator to run the prompt manually. The agent prompt is NOT modified — only the skill orchestrates.
8. **Render** — substitute placeholders in `templates/dashboard/index.html`: flat scalars via `envsubst`, nested arrays via `jq` filters. Write `<project>/dashboard/index.html`.

The parser contract `docs/specs/dashboard-build/parser-contract.md` is the canonical reference for every normalisation step and every exit code. This SKILL.md does not duplicate it; it points to it.

## Anti-patterns

- **`if ! cmd; then $?`** — bash 101 wrong. After `if ! cmd`, the `$?` inside the then-branch reads as 0 because the `!` test ran successfully, NOT the failed `cmd`. The contract exit codes from `parser-core.py` are silenced by this pattern. Always use `cmd || rc=$?` instead, then check `(( rc != 0 ))` separately. Demonstrated by `bash -c 'if ! (exit 20); then echo "captured: $?"; fi'` → `captured: 0` (B-3 ciclo 2/2 verbatim — caught by `@code-critic` after smoke adversarial fixture).
- **Hand-editing the intermediate JSON** — it is a derived artefact. Edit `backlog.md` instead, re-run the skill.
- **Editing `dashboard/index.html` directly** — same reason. The next run will overwrite. Speech edits go into the cycle commits / writeup, not the rendered HTML.
- **Bypassing the parser by writing to `state.json`** — there is no `state.json`; `backlog.md` is single source of truth per ADR-040. A separate `.dashboard/status.json` overlay exists only for transient `status` and `owner` overrides, not for card creation.
- **Mixing YAML frontmatter without opt-in** — ADR-040 canonical format is Markdown tables. The opt-in flag exists for migration cases only.
- **Modifying `agents/architect-ai.md`** — ADR-049 explicitly chose Option B (skill orchestration) over Option C (agent prompt expansion). Touching the agent prompt to add continuous-review behaviour reopens that decision and requires a superseding ADR.

## Current state (Wave 4, T11 closed) — full parser + hydrator wired

Per ADR-049 Addendum 2026-05-14 and T11 closure: the canonical-table parser is implemented in `skills/dashboard-build/parser-core.py` (Python 3.10+ stdlib only, ~930 LOC + `_lib/` modules `errors.py` 101 LOC and `hydrator.py` 292 LOC). `run.sh` shells out to `python3 parser-core.py --mode json` for JSON envelope emission and `--mode html` for full template hydration. Both global scalars (`__PROJECT_NAME__`, `__GENERATED_AT__`, ...) AND iterable placeholders (`__CARD_*__`, `__REVIEW_*__`, `__WARNING_*__`, `__OBJECTIVE_TEXT__`, etc.) are substituted; empty-state and conditional blocks resolve correctly.

**Hook `cycle-dashboard-enforcer.sh` (T7)** can now be wired as a real cycle gate — the dashboard rendered for a fully-populated backlog should contain zero literal `__VAR__` tokens. Integration test recommended: feed a fixture backlog.md through `python3 parser-core.py --mode html --project-root <fixture>` and assert `grep -c '__[A-Z_]\+__'` returns 0.

**Known debt registered (not blocking):**
- parser-core.py is 930 LOC (cap was ≤800). Split to `_lib/normalise.py` and `_lib/sidecars.py` is the next planned reduction; the current split (`_lib/errors.py`, `_lib/hydrator.py`) brought the largest concerns (error catalogue + HTML substitution) out of the main file. Acceptable as cycle-1 deliverable; future refactor lives in a follow-up cleanup task.
- Pyright reports `_lib` imports as unresolved when not running from the skill directory — this is a tooling false positive (`sys.path` is fixed at module load before the imports). Runtime is correct (`python3 -m py_compile parser-core.py` passes).

## Runtime requirements

- `bash` 4+ (strict mode `set -euo pipefail`, `IFS` reset).
- `jq` available on PATH (used by `run.sh` for the intermediate JSON envelope and for warning array merging in legacy paths — parser-core.py itself does not require `jq`).
- `python3 >= 3.10` available on PATH. Stdlib only (`re`, `json`, `pathlib`, `argparse`, `sys`, `os`, `html`, `logging`, `dataclasses`, `datetime`). **NO pip / third-party imports.** The skill aborts with exit code 102 (skill-level missing-sibling) if `python3` is absent or `parser-core.py` is not found.
- `sed`, `mktemp`, `realpath` (POSIX coreutils).

## Workspace requirement (`CLAUDE_PROJECT_DIR` override)

`run.sh` enforces `--project-root` to resolve via `realpath` to a path UNDER the repo workspace root (anti path-traversal). The workspace root is derived from `CLAUDE_PROJECT_DIR` when set, otherwise from `$PWD`.

The skill resolves TWO distinct roots, post-smoke-test fix (C-1):

1. **`SKILL_REPO_ROOT`** — derived from `SKILL_DIR/../..` (the location of THIS `run.sh`). Where the template, schema, and parser-contract live. **Independent of `CLAUDE_PROJECT_DIR`**. The skill is operable wherever the ARCA repo sits.
2. **`WORKSPACE_ROOT_ABS`** — derived from `CLAUDE_PROJECT_DIR` (or `$PWD` if unset). The path-traversal boundary that `--project-root` must resolve INSIDE. This is operator-controlled.

When the client project lives OUTSIDE `.claude/` (typical — projects under `~/projects/Projects/<other>/`), the operator exports `CLAUDE_PROJECT_DIR` to the **parent of the client project** (not necessarily the parent of ARCA — they are unrelated paths now). Example:

```bash
# Client project at ~/projects/Projects/voice-mini, ARCA repo is independent
CLAUDE_PROJECT_DIR="$HOME/projects/Projects" \
    bash "$HOME/projects/Projects/.claude/skills/dashboard-build/run.sh" \
    --project-root "$HOME/projects/Projects/voice-mini" \
    --cycle 5
```

Without the override, `realpath` resolves the client project outside the workspace prefix and the skill aborts with exit 101 (path-traversal defence). The override is the documented escape hatch and does NOT affect where the template / schema / contract are found.

**Smoke test reproducible**: `CLAUDE_PROJECT_DIR=/tmp bash <abs-path>/run.sh --project-root /tmp/<pilot> --cycle 1 --self-check` against a pilot project with `docs/c1-discovery/{backlog.md, problem-statement.md, success-metrics.md, stakeholders.md, objectives.md}` succeeds end-to-end and writes `<pilot>/dashboard/index.html` (~23 KB, zero unsubstituted iterable placeholders — only the doc-banner literal examples `__NAME__` and `__ITEM_FIELD__` remain inside the HTML comment block, which is intentional documentation, not content).

## Cross-references

- ADR-049 — mandates this skill and the continuous architecture review.
- ADR-040 — backlog Markdown-table canonical format.
- ADR-022 — every skill MUST carry this SKILL.md.
- ADR-008 — diff comprehension gate, sibling enforcement pattern.
- `docs/specs/dashboard-build/parser-contract.md` — full normalisation contract and error catalogue.
- `docs/specs/dashboard-build/schema.json` — output JSON shape.
- `templates/dashboard/index.html` — placeholder template owned by `@frontend-ai` (T5).
- `hooks/cycle-dashboard-enforcer.sh` — blocking hook (T7) that calls this skill.
- `skills/adr-new/SKILL.md` and `skills/adr-new/run.sh` — reference patterns for slug sanitisation, flock-serialised numbering, heredoc-safe argv passing.

## Invocation

All executable logic lives in `skills/dashboard-build/run.sh`. The skill page and the slash command (when created) are thin pointers — same separation as `skills/adr-new/`. The bash block invokes `run.sh` directly with sanitised argv; no `$ARGUMENTS` expansion crosses a shell layer that could re-evaluate it. For ad-hoc operator runs:

```bash
bash "${CLAUDE_PROJECT_DIR:-${PWD}}/skills/dashboard-build/run.sh" \
    --project-root "/abs/path/to/project" \
    --cycle 5
```

Add `--accept-yaml-frontmatter` for the opt-in mixed format or `--self-check` to force the `jq empty` post-emit verification.

## Stats

No bespoke stats file in v1. Exit code is the contract; downstream tooling (`cycle-dashboard-enforcer.sh`, CI) keys off it. A future `~/.claude/state/dashboard-build-stats.json` can be added when the operator volume justifies the bucket schema, on the same pattern as `auto-adr-stats.json`.
