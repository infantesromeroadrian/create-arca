---
name: eval-skeleton
description: Generate a minimal evals/scenarios/<agent>/scenario.json template by introspecting agents/<agent>.md frontmatter, phase assignment from CLAUDE.md pipeline, critic-gate exempt status, and the first distinctive keywords in the prompt body. Implements ADR-042 §3. HITL — the output contains explicit TODO markers the operator MUST refine before run_evals.py provides real signal. Refuses to overwrite an existing scenario.json (collision → abort). Activate when ⟦ user_name ⟧ says /eval-skeleton <agent>, generate eval skeleton for <agent>, prepárame un scenario.json para <agent>, or after the eval-suite-coverage-detector hook emits an [EVAL-COVERAGE WARN] line.
when_to_use: when an agent in agents/ has no sibling evals/scenarios/<agent>/scenario.json and the operator wants a template to start from (introspected frontmatter + phase + critic-gate status + keyword candidates). NOT for agents that already have a scenario file (refuses to overwrite), NOT for hand-tuning an existing scenario (edit it directly).
argument-hint: '<agent-name> [--json] [--force]'
disable-model-invocation: false
user-invocable: true
allowed-tools: Bash, Read, Write
model: sonnet
effort: low
---

# /eval-skeleton — Generate a starter scenario.json from agent introspection

Reduces the marginal cost of compliance with ADR-042 from "read evals/README.md and author from scratch" to "run command + refine the TODO markers". Implements ADR-042 §3 (skill generator).

## When to use

- An agent in `agents/<name>.md` has no `evals/scenarios/<name>/scenario.json` yet.
- The `[EVAL-COVERAGE WARN]` advisory just fired and the operator wants to close it.
- A new agent is being added to the harness and the eval suite should be wired in the same PR.

## When NOT to use

- The scenario file already exists — the skill aborts to avoid losing human-written checks. Pass `--force` only if the operator deliberately wants a fresh template (the old file should be backed up first).
- The agent prompt does not exist (typo or stale agent name) — the skill exits 1.
- For ad-hoc hand-tuning of an existing scenario — edit `evals/scenarios/<name>/scenario.json` directly.

## Inputs

| Flag | Default | Effect |
|---|---|---|
| `<agent-name>` | required | The agent slug (basename of `agents/<name>.md` without `.md`). |
| `--json` | off | Emit a JSON envelope summarizing what was written (machine-readable). Default is plain stdout. |
| `--force` | off | Overwrite an existing scenario.json. Operator opt-in only — protects against accidental loss. |

## Output (default plain)

```
=== eval-skeleton: @<agent> ===
  prompt path:        agents/<agent>.md
  scenario path:      evals/scenarios/<agent>/scenario.json
  model (frontmatter): opus
  phases detected:    C4, C8
  critic_gate_required: true
  keywords (TODO):    architecture, design, rationale, alternatives, ADR

Wrote evals/scenarios/<agent>/scenario.json (5 TODO markers).

Next step:
  Open the scenario file and replace [EVAL-SKELETON TODO] markers with
  agent-specific anti-patterns. Then run:  python3 evals/run_evals.py
```

## Output (--json)

```json
{
  "agent": "<agent>",
  "scenario_path": "evals/scenarios/<agent>/scenario.json",
  "frontmatter": {"model": "opus", "isolation": "worktree", "color": "blue"},
  "phases": ["C4", "C8"],
  "critic_gate_required": true,
  "keywords": ["architecture", "design", "rationale", "alternatives", "ADR"],
  "todo_markers": 5,
  "written": true
}
```

## Algorithm

1. Validate `<agent-name>` exists as `agents/<name>.md`.
2. Compute scenario path `evals/scenarios/<name>/scenario.json`. If it exists and `--force` is not set, exit 1.
3. Parse agent frontmatter (YAML between `---` fences at file head) — extract `model`, `isolation`, `color`, `tools`.
4. Compute pipeline phases by scanning the PHASE_AGENTS map in `evals/run_evals.py` (single source of truth). Agent slug → list of cycle keys it appears in.
5. Compute critic-gate-exempt status from CRITIC_GATE_EXEMPT in `evals/run_evals.py`. `critic_gate_required` = NOT in exempt set.
6. Extract up to 5 distinctive keywords from the prompt body — defined as the first 5 unique alphabetic tokens of length ≥ 5 that are NOT in a stop-list and NOT already in the frontmatter description.
7. Render scenario.json with TODO markers in `required_keywords` and a single stub case. Write to disk (mkdir -p first).
8. Bump the `skeleton_generated` counter in `~/.claude/state/eval-coverage-stats.json`.
9. Emit plain or JSON output. Exit 0.

## TODO markers

The generated scenario.json is intentionally incomplete. The operator MUST refine:

- `required_keywords`: the heuristic keyword list is a starting point. The operator should replace it with terms the agent prompt MUST mention to be considered correct for its role.
- `cases[*]`: the stub case is a placeholder. Real cases describe specific anti-patterns or required behaviors with `expected_keywords_in_prompt` matching the agent's actual domain.

All TODO sites are tagged with `EVAL-SKELETON TODO` so a grep across `evals/scenarios/` finds incomplete templates.

## Determinism

Same agent file + same `evals/run_evals.py` → same output. The keyword extraction is deterministic (first 5 tokens passing the filter, by position in the prompt). No LLM calls.

## Failure modes

- Agent prompt missing → exit 1.
- Scenario file exists without `--force` → exit 1, message on stderr telling the operator to delete or use `--force`.
- Frontmatter unparseable (missing `---` fences) → exit 1.
- jq missing → exit 1 (used for safe JSON shaping).
- `evals/run_evals.py` missing → emit a degraded scenario with `expected_phases=["all"]` and `critic_gate_required=false`, warn on stderr.

## Composition

- Composes with ADR-042 (the coverage invariant this skill helps satisfy).
- Composes with `hooks/eval-suite-coverage-detector.sh` — the hook emits the advisory; this skill closes it.
- Composes with `evals/run_evals.py` — once the operator refines the TODOs, run_evals validates the scenario against the actual prompt.

## Examples

```bash
# Generate skeleton for a recently-added agent
/eval-skeleton agent-engineer

# Inspect what would be generated (JSON output) without prose
/eval-skeleton mlops-engineer --json

# Regenerate (deliberately overwrite an existing scenario)
/eval-skeleton tester --force
```
