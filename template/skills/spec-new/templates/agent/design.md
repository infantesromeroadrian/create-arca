---
feature: {{FEATURE}}
slug: {{SLUG}}
type: {{TYPE}}
created: {{DATE}}
status: Draft
related_adr: <TODO: ADR-NNN>
related_excalidraw: <TODO: docs/architecture/{{SLUG}}.excalidraw>
---

# Design — {{FEATURE}} (LLM Agent)

> Decisiones arquitecturales viven en `docs/adr/NNN-{{SLUG}}.md`.

## 1. Architecture summary

<TODO: 1 parrafo. Pattern (ReAct/ReWOO/...). State machine. Tool palette. Memory. HITL gates.>

Reference: [ADR-NNN](../../adr/NNN-{{SLUG}}.md)
Diagrama: [{{SLUG}}.excalidraw](../../architecture/{{SLUG}}.excalidraw)

## 2. Components affected

| Component | Type | Action | Owner agent |
|---|---|---|---|
| `agents/{{SLUG}}/graph.py` | LangGraph state machine | Create | `@agent-engineer` |
| `agents/{{SLUG}}/tools/` | Tool definitions | Create | `@agent-engineer` |
| `agents/{{SLUG}}/prompts/` | System + tool prompts | Create | `@prompt-engineer` |
| `agents/{{SLUG}}/sandbox/Dockerfile` | Tool execution sandbox | Create | `@devops` |
| `evals/{{SLUG}}_tasks.jsonl` | Golden task set | Create | `@evals-engineer` |
| `services/agent_runner_{{SLUG}}.py` | Runtime + HITL | Create | `@ai-production-engineer` |
| `grafana/dashboards/agent_{{SLUG}}.json` | Per-step + cost dashboard | Create | `@monitoring` |

## 3. State machine (LangGraph)

<TODO: pseudocode states + transitions. Obligatorio si pattern es LangGraph.>

```python
# agents/{{SLUG}}/graph.py (excerpt)
from langgraph.graph import StateGraph, END

graph = StateGraph(AgentState)
graph.add_node("plan", plan_node)
graph.add_node("execute_tool", execute_tool_node)
graph.add_node("reflect", reflect_node)
graph.add_node("hitl_approval", hitl_approval_node)
graph.add_node("finalize", finalize_node)

graph.add_edge("plan", "execute_tool")
graph.add_conditional_edges("execute_tool",
    lambda s: "hitl_approval" if s.tool_destructive else "reflect")
graph.add_edge("hitl_approval", "execute_tool")
graph.add_conditional_edges("reflect",
    lambda s: "finalize" if s.done or s.iter >= MAX_ITER else "plan")
graph.add_edge("finalize", END)
```

## 4. Tool palette

| Tool | Implementation | Sandboxed? | Destructive? | Permission scope |
|---|---|---|---|---|
| `<tool_1>` | <TODO: lib + version> | yes (Docker) | no | <scope> |
| `<tool_2>` | <TODO> | yes (Docker) | yes | requires HITL |

Each tool wrapped with:
- Timeout (per-tool config)
- Budget cap (token cost per call)
- Rate limit (calls/min/agent)
- Output schema validation

## 5. Tech stack choices

| Concern | Choice | Justification |
|---|---|---|
| Framework | <TODO: LangGraph | LangChain | custom> | <TODO: ADR ref> |
| LLM | <TODO: Claude Sonnet 4.6 | Opus 4.8 | Qwen local> | <TODO: cost / capability tradeoff> |
| Sandbox | <TODO: Docker | Firecracker | gVisor> | <TODO: isolation level> |
| State persistence | <TODO: LangGraph checkpointer postgres | redis | sqlite> | <TODO> |
| Observability | LangSmith + OpenTelemetry + Prometheus + Grafana MCP | ARCA default |

## 6. Trade-offs

| Decision | Chosen | Alternatives rejected | Reason |
|---|---|---|---|
| ReAct vs ReWOO | <TODO> | <TODO> | <TODO: token cost vs flexibility> |
| LLM Sonnet vs Opus | <TODO> | <TODO> | <TODO: cost vs capability per task type> |
| Sandboxing Docker vs Firecracker | <TODO> | <TODO> | <TODO: startup latency vs isolation> |

Detalle: [ADR-NNN](../../adr/NNN-{{SLUG}}.md).

## 7. Failure modes + mitigation (CRITICAL — agent loops are bombs)

| Failure | Detection | Mitigation |
|---|---|---|
| Infinite loop | iter > MAX_ITER | Hard stop + log + alert |
| Budget exhaust | running token cost > cap | Abort with refusal + receipt |
| Tool timeout | per-tool timer | Kill process + retry once + abort |
| Prompt injection (input) | Rebuff/NeMo classifier | Refuse + log + alert |
| Indirect prompt injection (tool output) | Output classifier | Sanitize + flag + continue or abort |
| Sandbox escape attempt | Docker syscall audit | Kill container + alert P1 |
| Destructive action without approval | HITL gate enforced | Block + ask ⟦ user_name ⟧ / user |
| Hallucinated tool name | Allowlist check | Refuse + log |
| Tool API key leaked in trace | PII redaction layer | Mask + audit |

## 8. Security posture (OWASP LLM Top 10:2025 mapping)

| OWASP LLM | Mitigation |
|---|---|
| LLM01 Prompt Injection | Rebuff input + output classifier + system prompt isolation |
| LLM02 Insecure Output Handling | Output schema validation + sanitization |
| LLM03 Training Data Poisoning | n/a (agent uses external LLM API) |
| LLM04 Model DoS | Budget cap + rate limit + max_iter |
| LLM05 Supply Chain | Tool palette signed allowlist |
| LLM06 Sensitive Info Disclosure | PII redaction in logs + secrets via Vault |
| LLM07 Insecure Plugin Design | Sandbox + permission scoping + HITL |
| LLM08 Excessive Agency | HITL for destructive + limited tool palette |
| LLM09 Overreliance | User UI shows AI label + citations |
| LLM10 Model Theft | n/a (external API) |

## 9. Observability spec

### 9.1 Metrics (Prometheus)

- `agent_iter_count` histogram per task
- `agent_tool_call_total{tool,status}` counter
- `agent_tool_latency_seconds{tool}` histogram
- `agent_task_latency_seconds` histogram E2E
- `agent_task_cost_usd` histogram
- `agent_refusal_total` counter
- `agent_hitl_approval_total{decision}` counter
- `agent_sandbox_violation_total` counter

### 9.2 Traces (OpenTelemetry + LangSmith)

- Root span: `agent.task`
- Child spans: `agent.plan`, `agent.tool.<name>`, `agent.reflect`, `agent.hitl`
- LangSmith run linked via trace_id

### 9.3 Dashboard (Grafana MCP)

Path: `grafana/dashboards/agent_{{SLUG}}.json`. Panels:

1. Task completion rate
2. Iter count distribution
3. Cost per task trend
4. Tool failure rate per tool
5. HITL approval/rejection rate
6. Sandbox violations (anomaly detection P1)
7. Refusal rate trend
8. Latency E2E p50/p95/p99

## 10. Compliance posture

| Regulation | Article | Applicable | Evidence |
|---|---|---|---|
| GDPR | Art 22 | <TODO> | HITL + opt-out endpoint |
| EU AI Act | Art 14 | yes | HITL gates documented + approval log |
| EU AI Act | Art 50 | yes | "AI agent" label + content provenance |
| EU AI Act | Art 52 | <TODO> | Risk management si high-risk |
| SOC 2 | CC8.1 | yes | Per-step audit trail |
| OWASP LLM Top 10:2025 | full | yes | Mitigation matrix above |

## 11. Rollback plan

1. Feature flag flip → disable agent for new tasks (existing finish or abort)
2. LangGraph state machine version pin previous
3. Tool palette revert to known-good signed allowlist
4. RTO target: <TODO: NN min>

## 12. Open questions

- <TODO>
