---
feature: {{FEATURE}}
slug: {{SLUG}}
type: {{TYPE}}
created: {{DATE}}
status: Draft
related_adr: <TODO: ADR-NNN>
---

# Tasks — {{FEATURE}} (RAG system)

## Cycle mapping

| Cycle | Tasks |
|---|---|
| C1 Discovery | T-001 |
| C2 Data | T-002 |
| C4 Design | T-003 |
| C5 POC | T-004 |
| C6 Build | T-005..T-009 |
| C8 Quality | T-010, T-011 |
| C9 Pre-prod | T-012 |
| C10 Deploy | T-013 |
| C12 Monitoring | T-014 |

## Tasks

### T-001 — Requirements firmados

- **Cycle:** C1 · **Owner:** `@project-planner` + `@rag-engineer` · **Effort:** 2h
- Completar `requirements.md`. Acceptance criteria RAGAS targets numerados.
- **Gate:** `@project-planner` + ⟦ user_name ⟧.

### T-002 — Corpus validation + ingest plan

- **Cycle:** C2 · **Owner:** `@data-engineer` + `@rag-engineer` · **Effort:** 4h · **Depends:** T-001
- Source schema verified, PII redaction plan, access control plan, ACL extraction.
- **Gate:** `@data-validator`.

### T-003 — Architecture + ADR

- **Cycle:** C4 · **Owner:** `@architect-ai` + `@rag-engineer` · **Effort:** 4h · **Depends:** T-002
- ADR firmado, design.md TODOs cerrados (chunking, embed, retrieval, rerank, generation choices), Excalidraw.
- **Gate:** `@architect-ai`.

### T-004 — POC end-to-end minimal

- **Cycle:** C5 · **Owner:** `@rag-engineer` · **Effort:** 6h · **Depends:** T-003
- Pipeline minimal: ingest 10 docs → chunk → embed → store → retrieve → generate. Eval rapida vs golden 20 questions.
- **Gate:** Faithfulness ≥ baseline (0.7) o abort.

### T-005 — Ingest pipeline production

- **Cycle:** C6 · **Owner:** `@data-engineer` + `@rag-engineer` · **Effort:** 5h · **Depends:** T-004
- Loader full corpus, chunking strategy, metadata extraction, idempotent re-ingest, scheduled cron.
- **Gate:** `@code-critic`.

### T-006 — Embedding pipeline + index build

- **Cycle:** C6 · **Owner:** `@rag-engineer` + `@math-critic` · **Effort:** 4h · **Depends:** T-005
- Embed batch processing, vector store schema, HNSW params tuning. Hash determinism.
- **Gate:** `@math-critic` (embedding metrics validation) → `@code-critic`.

### T-007 — Retrieval + rerank service

- **Cycle:** C6 · **Owner:** `@rag-engineer` · **Effort:** 5h · **Depends:** T-006
- Hybrid retrieval (si elegido), top-K, score threshold, refusal logic, reranker integration, ACL filter.
- **Gate:** `@code-critic`.

### T-008 — Generation + citation service

- **Cycle:** C6 · **Owner:** `@rag-engineer` + `@ai-engineer` · **Effort:** 5h · **Depends:** T-007
- Prompt template, structured output con citations, refusal pattern, response sanitization.
- **Gate:** `@code-critic`.

### T-009 — Guardrails (input + output)

- **Cycle:** C6 · **Owner:** `@trust-and-safety-engineer` + `@ai-production-engineer` · **Effort:** 4h · **Depends:** T-008
- Prompt injection detection (input + indirect via retrieved docs), PII leak classifier, toxicity, citation accuracy regex.
- **Gate:** `@trust-and-safety-engineer` sign-off.

### T-010 — RAGAS eval suite + golden Q&A

- **Cycle:** C8 · **Owner:** `@rag-engineer` + `@math-critic` · **Effort:** 5h · **Depends:** T-008
- Golden Q&A ≥ 100 curated. RAGAS faithfulness/relevance/precision/recall. Statistical significance bootstrap.
- **Gate:** `@math-critic` valida metrics interpretation.

### T-011 — Tests coverage ≥ 80%

- **Cycle:** C8 · **Owner:** `@tester` · **Effort:** 4h · **Depends:** T-010
- Unit (chunking, embedding shape, retrieval), integration (end-to-end pipeline), eval suite as test gate.
- **Gate:** `@tester` (BLOQUEANTE).

### T-012 — Pre-prod validation

- **Cycle:** C9 · **Owner:** `@deployment` + `@ai-production-engineer` · **Effort:** 4h · **Depends:** T-011
- Shadow staging 7d. Latency p95 SLA. Cost per query measured. Adversarial prompts batch (red team).
- **Gate:** `@deployment` + `@ai-red-teamer` review si R2 fired.

### T-013 — Production deploy

- **Cycle:** C10 · **Owner:** `@deployment` + `@chief-architect` · **Effort:** 3h · **Depends:** T-012
- Canary 5% → 100%. Auto-rollback en RAGAS quality degradation o latency breach.
- **Gate:** `@chief-architect` (BLOQUEANTE).

### T-014 — Monitoring + retraining triggers

- **Cycle:** C12 · **Owner:** `@monitoring` + `@ai-production-engineer` · **Effort:** 3h · **Depends:** T-013
- Dashboards Grafana MCP. RAGAS sampling 1-5% async. Reindex trigger configured (corpus drift).
- **Gate:** `@monitoring` sign-off.

## Total effort estimate

<TODO: 2+4+4+6+5+4+5+5+4+5+4+4+3+3 = 58h>

## Risks during execution

| Risk | Likelihood | Mitigation |
|---|---|---|
| RAGAS faithfulness < target | M | Iterate chunking + reranker; fallback refusal |
| Retrieval latency excede SLA | M | HNSW params tuning, caching frequent queries |
| Indirect prompt injection via corpus | M | Output classifier mandatory + system prompt isolation |
| Cost per query excede budget | L | Cheaper embeddings + smaller LLM + cache |
