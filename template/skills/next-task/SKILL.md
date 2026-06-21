---
name: next-task
description: Read the canonical project backlog at <project>/docs/c1-discovery/backlog.md, parse the MoSCoW + RICE Markdown table (per ADR-040), filter to entries whose dependencies are resolved, sort by RICE descending, and return the next pending entry as structured JSON. Activate when ⟦ user_name ⟧ says /next-task, what should I work on next, what is the highest-RICE pending item, or similar planning-prioritization queries within an ARCA project.
when_to_use: when ⟦ user_name ⟧ wants to know the next prioritized backlog item to start. NOT for ad-hoc todo lists, ephemeral session work, or non-canonical backlogs (those have no deterministic prioritization).
argument-hint: '[--completed=BL-001,BL-002,...] [--moscow=MUST,SHOULD,COULD] [--top=N] [--backlog=PATH] [--plain]'
disable-model-invocation: false
user-invocable: true
allowed-tools: Bash, Read
model: sonnet
effort: low
---

# /next-task — Backlog prioritization consumer

Reads the canonical `<project>/docs/c1-discovery/backlog.md` validated against ADR-040 and returns the next entry to work on, sorted by RICE descending and filtered by dependency resolution.

## When to use

- ⟦ user_name ⟧ asks "what should I work on next" within an ARCA project that has a backlog.
- Need a deterministic, RICE-prioritized handoff between sprints.
- Want to know which items are unblocked given a set of already-completed items.

## When NOT to use

- The project does not ship a backlog at the canonical path. Inferring priority from ad-hoc files is out of scope.
- Pre-C1 projects (no Discovery cycle closed yet) do not have a backlog to read.
- Ecosystem repos (`.claude`, `your-snapshots-repo`, `your-vault-repo`) — they are the harness, not pipeline projects.

## Inputs

All optional. Defaults assume invocation from inside the project root (the CWD that has `docs/c1-discovery/backlog.md`).

| Flag | Default | Effect |
|---|---|---|
| `--completed=ID,ID,...` | empty | Mark these BL-NNN as already-done. Two effects: (a) entries depending only on these become eligible; (b) the IDs themselves are excluded from the candidate pool — "what's next" means new work, not re-recommendation. |
| `--moscow=CLASS,CLASS,...` | `MUST,SHOULD,COULD` | Restrict the candidate pool to these classes. WON'T is always excluded. |
| `--top=N` | `1` | Return the top N eligible entries (RICE descending). |
| `--backlog=PATH` | `<cwd>/docs/c1-discovery/backlog.md` | Override the canonical path. |
| `--plain` | off | Human-readable output instead of JSON. |

## Output (default JSON)

```json
{
  "backlog_path": "/abs/path/backlog.md",
  "criteria": {
    "completed": ["BL-006"],
    "moscow": ["MUST", "SHOULD", "COULD"],
    "top": 1
  },
  "results": [
    {
      "id": "BL-007",
      "title": "C5 POC — minimal voice loop end-to-end",
      "type": "Integration",
      "cycle": "C5",
      "story_pts": "8",
      "moscow": "MUST",
      "rice": 35.0,
      "deps": ["BL-006"],
      "deps_resolved": true
    }
  ]
}
```

If no eligible entry exists, `results` is an empty array (exit 0). The caller treats that as "no unblocked work".

## Algorithm

1. Resolve backlog path. If the path does not exist, exit 1 with a clear message.
2. Parse the file linearly (same parser as `hooks/backlog-format-validator.sh`):
   - Track current MoSCoW class header.
   - Skip header / separator rows.
   - Build an entry per data row: id, title, type, cycle, story_pts, reach, impact, conf, effort, rice, deps, moscow.
3. Filter:
   - Drop WON'T entries unconditionally.
   - Drop entries whose `id` is in `--completed` (already done — not next).
   - Keep only entries whose `moscow` is in `--moscow`.
   - Compute `deps_resolved` = (deps empty) OR (every dep ∈ `--completed`).
   - Drop entries where `deps_resolved` is false.
4. Sort remaining by `rice` descending.
5. Truncate to `--top` entries.
6. Emit JSON (or plain text if `--plain`).

## Determinism

The skill does not mutate state, does not call the network, does not invoke an LLM. Same backlog + same flags → same output. Stats are not persisted (this is a read-only consumer).

## Failure modes

- Backlog file missing → exit 1, message on stderr.
- Backlog malformed → the validator hook would have caught it on the prior `Edit`/`Write`. The skill does not re-validate; it parses best-effort and skips rows it cannot interpret. Non-fatal.
- No eligible entry → exit 0, empty `results`.
- jq missing → exit 1 (jq is the JSON shaper).

## Composition

- Composes with ADR-040 (the schema this skill consumes).
- Composes with ADR-022 / ADR-037 (single source + denylist patterns).
- Composes with ADR-027 (Spec-Driven Development) — feeds the same `features.json`-shaped semantic content but in Markdown form.

## Examples

```bash
# Default — single highest-RICE unblocked MUST/SHOULD/COULD item
/next-task

# What's next given BL-006 is done
/next-task --completed=BL-006

# Top 3 MUST items
/next-task --moscow=MUST --top=3

# Human-readable output
/next-task --plain

# Force a specific backlog
/next-task --backlog=/abs/path/backlog.md
```
