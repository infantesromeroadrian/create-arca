---
feature: {{FEATURE}}
slug: {{SLUG}}
type: {{TYPE}}
created: {{DATE}}
status: Draft
owner: ⟦ user_name ⟧ (single-dev)
related_adr: <TODO: ADR-NNN>
triggers_fired: [<TODO: R1 | R2 | R3 | R4>]
---

# Requirements — {{FEATURE}} (LLM Agent)

## 1. Business goal

<TODO: que tarea autonoma resuelve. Por que agent vs chain vs simple LLM. Coste de no tenerlo.>

## 2. Stakeholders

| Role | Identity | Concern |
|---|---|---|
| Owner | ⟦ user_name ⟧ | <TODO> |
| Tool maintainer | <TODO> | tool API stability, deprecation |
| Compliance | <TODO> | audit trail of agent actions, HITL for destructive ops |
| End user | <TODO> | task completion rate, latency, transparency |

## 3. Acceptance criteria

- **AC-001** Task completion rate ≥ <TODO: 0.85> sobre golden task set (n ≥ 50).
- **AC-002** Max iterations cap: <TODO: 10> — agent termina con respuesta o refusal.
- **AC-003** Per-tool timeout: <TODO: 30s>.
- **AC-004** Budget cap per task: <TODO: $0.50 USD> (token cost).
- **AC-005** HITL approval requerida antes de actions destructivas (delete / mass send / financial txn).
- **AC-006** Sandbox: tool execution en Docker / Firecracker isolated, sin acceso filesystem host.
- **AC-007** Permission scoping: tool palette restringida por user role / use case.
- **AC-008** Latency p95 task end-to-end ≤ <TODO: NN s>.
- **AC-009** Audit log: cada step (thought + tool call + observation) persisted con trace_id.

## 4. Tools palette

<TODO: lista herramientas. Cada una con justificacion + permisos + budget.>

| Tool | Purpose | Permission scope | Budget per call | Destructive? |
|---|---|---|---|---|
| `<tool_1>` | <TODO> | <read | write | exec> | <NN tokens / $> | <yes / no> |
| `<tool_2>` | <TODO> | <TODO> | <TODO> | <TODO> |

## 5. Agent pattern

| Concern | Choice | Justification |
|---|---|---|
| Pattern | <TODO: ReAct | ReWOO | Plan-and-Execute | Reflexion | LangGraph state machine> | <TODO: ADR ref> |
| Memory | <TODO: short-term only | long-term Engram-style | episodic> | <TODO> |
| Termination | <TODO: max_iter | budget exhausted | task done | refusal> | <TODO> |

## 6. Non-functional requirements

### 6.1 Performance

- Latency p95: <TODO: NN s>
- Tool call rate: <TODO: avg NN per task>
- Token consumption per task: <TODO: avg / p95>

### 6.2 Security (CRITICAL — agentic loops are bombs)

- Sandboxing: <TODO: Docker | Firecracker | gVisor> obligatorio para tool execution.
- Permission scope fine-grained per tool.
- Prompt injection detection (input + indirect via tool outputs).
- Output filtering: PII leak, toxicity, jailbreak.
- Tool palette signed allowlist; no dynamic tool loading.
- Rate limit per tenant (max tasks/hour).

### 6.3 HITL (Human-in-the-loop)

- Destructive actions require explicit approval via UI or chat (per CLAUDE.md security rules).
- Approval timeout: <TODO: 5 min> → abort si no respuesta.
- Audit log every approval/rejection.

### 6.4 Compliance

- EU AI Act Art 14 (human oversight): mandatory para high-risk classification.
- EU AI Act Art 50 (transparency): user must know they interact with AI agent.
- GDPR Art 22: si agent toma decisions automated → opt-out endpoint.
- SOC 2 CC8.1: audit trail completo de cada step.

### 6.5 Observability

- Per-step traces (OpenTelemetry): thought / tool / observation.
- Trace IDs propagated through tool calls.
- Cost per task (token attribution per prompt + tool).
- Iteration count distribution.
- Tool failure rate per tool.
- Refusal rate.

## 7. Out of scope

- <TODO: e.g. multi-agent collaboration>
- <TODO: e.g. agent self-modification / code generation>

## 8. References

- ADR linked: `docs/adr/<TODO: NNN-slug.md>`
- ARCA agents involucrados: `@agent-engineer`, `@ai-engineer`, `@trust-and-safety-engineer`, `@ai-production-engineer`, `@math-critic`, `@monitoring`
- Related skills: `langgraph`, `ai-agents-engineering`, `langchain-middleware`
