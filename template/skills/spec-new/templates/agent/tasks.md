---
feature: {{FEATURE}}
slug: {{SLUG}}
type: {{TYPE}}
created: {{DATE}}
status: Draft
related_adr: <TODO: ADR-NNN>
---

# Tasks — {{FEATURE}} (LLM Agent)

## Cycle mapping

| Cycle | Tasks |
|---|---|
| C1 Discovery | T-001 |
| C4 Design | T-002, T-003 |
| C5 POC | T-004 |
| C6 Build | T-005..T-010 |
| C8 Quality | T-011, T-012 |
| C9 Pre-prod | T-013 |
| C10 Deploy | T-014 |
| C12 Monitoring | T-015 |

## Tasks

### T-001 — Requirements firmados

- **Cycle:** C1 · **Owner:** `@project-planner` + `@agent-engineer` · **Effort:** 2h
- Tools palette enumerada con permisos, budget, destructive flag. Acceptance criteria numericos.
- **Gate:** `@project-planner` + ⟦ user_name ⟧.

### T-002 — Architecture + ADR

- **Cycle:** C4 · **Owner:** `@architect-ai` + `@agent-engineer` · **Effort:** 4h · **Depends:** T-001
- Pattern decision (ReAct/ReWOO/...), state machine design, sandboxing strategy, ADR firmado, Excalidraw.
- **Gate:** `@architect-ai`.

### T-003 — Tool palette signed allowlist

- **Cycle:** C4 · **Owner:** `@agent-engineer` + `@trust-and-safety-engineer` · **Effort:** 3h · **Depends:** T-002
- Lista cerrada de tools. Cada uno con schema, permission scope, destructive flag, budget. Signed manifest.
- **Gate:** `@trust-and-safety-engineer` sign-off.

### T-004 — POC end-to-end minimal

- **Cycle:** C5 · **Owner:** `@agent-engineer` · **Effort:** 6h · **Depends:** T-003
- LangGraph minimal con 2 tools, max_iter=5, golden 10 tasks. Eval task completion rate.
- **Gate:** Completion rate ≥ baseline (0.6) o abort.

### T-005 — State machine production-grade

- **Cycle:** C6 · **Owner:** `@agent-engineer` · **Effort:** 8h · **Depends:** T-004
- LangGraph completo, all states, conditional edges, checkpointer config, error handling.
- **Gate:** `@code-critic`.

### T-006 — Tool implementations + sandbox

- **Cycle:** C6 · **Owner:** `@agent-engineer` + `@devops` · **Effort:** 6h · **Depends:** T-005
- Tools wrapped con timeout / budget / rate limit. Docker sandbox image built + signed.
- **Gate:** `@code-critic` + `@devops`.

### T-007 — HITL approval workflow

- **Cycle:** C6 · **Owner:** `@agent-engineer` + `@frontend-ai` · **Effort:** 4h · **Depends:** T-005
- Destructive actions blocked by HITL gate. Approval UI + chat fallback. Timeout abort.
- **Gate:** `@code-critic`.

### T-008 — Guardrails (input + output)

- **Cycle:** C6 · **Owner:** `@trust-and-safety-engineer` + `@ai-production-engineer` · **Effort:** 4h · **Depends:** T-006
- Rebuff input. Output classifier (PII / toxicity / jailbreak). Indirect prompt injection detection en tool outputs.
- **Gate:** `@trust-and-safety-engineer` sign-off.

### T-009 — Observability instrumentation

- **Cycle:** C6 · **Owner:** `@monitoring` + `@ai-production-engineer` · **Effort:** 4h · **Depends:** T-005..T-008
- Per-step Prometheus metrics, OpenTelemetry traces, LangSmith integration. Grafana dashboard via MCP.
- **Gate:** `@monitoring`.

### T-010 — Cost ops + budget enforcement

- **Cycle:** C6 · **Owner:** `@ai-production-engineer` · **Effort:** 2h · **Depends:** T-009
- Per-tenant token budget cap. Streaming token counting. Cost anomaly detection. Per-feature attribution.
- **Gate:** `@code-critic`.

### T-011 — Capability + dangerous capability evals

- **Cycle:** C8 · **Owner:** `@evals-engineer` + `@math-critic` · **Effort:** 5h · **Depends:** T-010
- Golden tasks ≥ 50. Capability evals (HumanEval-style si aplicable). Dangerous capability evals (autonomy + R&D acceleration).
- **Gate:** `@evals-engineer` sign-off.

### T-012 — Tests coverage ≥ 80% + adversarial

- **Cycle:** C8 · **Owner:** `@tester` + `@ai-red-teamer` · **Effort:** 5h · **Depends:** T-011
- Unit (state transitions, tool wrappers), integration (full graph), red team (prompt injection, sandbox escape, budget bypass).
- **Gate:** `@tester` (BLOQUEANTE) + `@ai-red-teamer` si R2 fired.

### T-013 — Pre-prod validation

- **Cycle:** C9 · **Owner:** `@deployment` + `@ai-production-engineer` · **Effort:** 4h · **Depends:** T-012
- Shadow staging 7d. Latency p95. Cost per task. Game day: trigger sandbox violation, verify alert.
- **Gate:** `@deployment`.

### T-014 — Production deploy con HITL gates

- **Cycle:** C10 · **Owner:** `@deployment` + `@chief-architect` · **Effort:** 3h · **Depends:** T-013
- Canary 5% → 100%. Auto-rollback on completion rate drop o sandbox violations. HITL approval workflow LIVE.
- **Gate:** `@chief-architect` (BLOQUEANTE).

### T-015 — Monitoring + abuse detection

- **Cycle:** C12 · **Owner:** `@monitoring` + `@trust-and-safety-engineer` · **Effort:** 3h · **Depends:** T-014
- Dashboards live. Abuse pattern detection (rate analysis + clustering). Sandbox violation alerts P1. Cost anomaly alerts.
- **Gate:** `@monitoring` + `@trust-and-safety-engineer`.

## Total effort estimate

<TODO: 2+4+3+6+8+6+4+4+4+2+5+5+4+3+3 = 63h>

## Risks during execution

| Risk | Likelihood | Mitigation |
|---|---|---|
| Sandbox escape vulnerability | L | `@ai-red-teamer` red team mandatory before T-014 |
| Infinite loop o budget runaway | M | Hard caps + monitoring + circuit breakers |
| HITL fatigue (⟦ user_name ⟧ aprueba todo sin leer) | H | UI shows clear context + impact assessment + cost |
| Prompt injection bypassa guardrails | M | Defense in depth: input + output + system prompt isolation + tool palette |
| Tool API breaking change | M | Pin versions + integration tests in CI |

## Status tracking

Estado en Obsidian `Projects/<project>/Status.md`. Re-hash `spec.lock.json` al completar tasks.
