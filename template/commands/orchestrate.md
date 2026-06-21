---
description: Dynamic Orchestration (ADR-089). @architect-ai proposes a bespoke agent DAG (which subagents, what order, which adversarial critics + blocking gates per node) for a task that does not fit the fixed ML/HTB/ART pipelines. ⟦ user_name ⟧ approves before any agent executes. Usage, /orchestrate <task>. Flag --ephemeral for a throwaway per-thread plan.
---

# /orchestrate — Dynamic Orchestration (ADR-089)

The 4th orchestration mode. The fixed pipelines (`/ml-new`, `/htb-new`, `/redteam-new`)
are untouched and remain authoritative. `/orchestrate` is the **catch-all for the long
tail** — codebase refactors, security-tooling builds, one-off data migrations, multi-agent
research — anything that wants a *bespoke* subset of the 57-agent roster wired in a
task-specific order, with task-specific critics and blocking gates.

## Usage

```
/orchestrate refactor the auth module to hexagonal architecture
/orchestrate audit the whole repo for hardcoded secrets
/orchestrate migrate the feature store from CSV to Parquet
/orchestrate --ephemeral quick spike: does library X fit our pipeline
```

## The contract: propose → validate → approve → execute

1. **Preflight (mandatory, non-skippable):** `@token-optimizer` compresses the task
   context (≤670 tokens), then `@skill-router` selects ≤3 skills. The
   `delegation-preflight-enforcer.sh` hook blocks any specialist invoked without these.

2. **Propose:** `@architect-ai` analyzes the task and emits an **Orchestration Proposal**
   conforming to `hooks/lib/orchestration-proposal-schema.json` — a DAG of nodes where
   each node declares: which roster agent, its dependencies (order), its isolation
   (worktree vs none), its success criteria, and **the adversarial critics + blocking
   gates wired into it**. If the task clearly matches ML/HTB/ART, the proposal instead
   **recommends the fixed pipeline** (`template_recommendation`) and does not greenfield.

3. **Validate (Layer 1 — schema floor):** `hooks/lib/validate-orchestration-proposal.sh`
   runs against the proposal. It **rejects** any proposal that under-declares a mandatory
   critic per node-type — ⟦ user_name ⟧ never sees an under-gated DAG. The floor:
   - `ml/dl/ai-engineer` node → must declare `math-critic → debt-detector → code-critic`.
   - any of the 17 code-producing agents → `debt-detector → code-critic`.
   - node that produces a deployable → `code-critic → chief-architect`.
   - node hitting the 7 adversarial signals → `ai-red-teamer`.
   - any code-producing DAG → must declare a terminal closer node.

4. **Approve (mandatory gate):** the proposal is presented to ⟦ user_name ⟧ with
   `approval.status: PENDING_⟦ user_name ⟧`. **No node executes until ⟦ user_name ⟧ flips it to
   APPROVED.** This is a schema-mandated step, not a courtesy.

5. **Persist (cadence):**
   - **per-project (default):** the approved proposal is written to
     `docs/architecture/<project>-orchestration.json` and saved to Engram
     (`orchestration/<project>-<date>`). It survives compaction and `/resume`.
     Re-running `/orchestrate` on the same project produces a **diff** proposal for
     re-approval, never a silent overwrite.
   - **per-thread (`--ephemeral`):** the plan is not persisted — for throwaway spikes.

6. **Execute:** the orchestrator runs the DAG node by node, honoring `depends_on` order.
   The runtime enforcers fire on every `Agent` invocation regardless of what the plan
   declared (Layer 2):
   - the 3 existing enforcers (preflight / math-critic / code-critic gates), plus
   - `dynamic-orchestration-gate-enforcer.sh`, which treats the DAG's declared terminal
     node as an additional phase-closer — so a code-producing DAG that ends on a node
     other than `@chief-architect`/`@deployment` still trips the code-critic gate.

## Why two enforcement layers

The planner is **never** trusted to be the only line of defense. Layer 1 rejects an
under-gated proposal at declaration time; Layer 2 hard-blocks at invocation time even if
Layer 1 had a gap. **Trust the hooks, not the plan** (ADR-089 § Gate-Enforcement Mechanism).

## What the planner cannot do

Remove a mandatory critic (schema rejects) · disable any enforcer hook · invoke a closer
without a prior `@code-critic` (runtime blocks) · skip the preflight · execute any node
before ⟦ user_name ⟧'s approval.

## Compound handoff

If the proposed DAG trips the compound decision matrix (>2 coordinated LLM calls /
verifier-in-loop / multi-provider routing), `@architect-ai` hands the orchestration design
to `@compound-ai-architect` — `/orchestrate` does not absorb compound-system design.

See ADR-089 (`docs/adr/089-dynamic-orchestration.md`).
