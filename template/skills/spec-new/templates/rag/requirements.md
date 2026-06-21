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

# Requirements — {{FEATURE}} (RAG system)

## 1. Business goal

<TODO: que pregunta-respuesta resuelve. Por que RAG vs solo LLM. Por que ahora.>

## 2. Stakeholders

| Role | Identity | Concern |
|---|---|---|
| Owner | ⟦ user_name ⟧ | <TODO> |
| Domain expert | <TODO> | content accuracy, terminology |
| Compliance | <TODO> | source attribution, GDPR data minimization |
| End user | <TODO: internal team / customer / regulator> | answer quality, latency |

## 3. Acceptance criteria

- **AC-001** Faithfulness ≥ <TODO: 0.85> (RAGAS metric, n ≥ 100 questions).
- **AC-002** Answer relevance ≥ <TODO: 0.80> (RAGAS).
- **AC-003** Context precision ≥ <TODO: 0.75> (RAGAS).
- **AC-004** Context recall ≥ <TODO: 0.80> (RAGAS).
- **AC-005** Hallucination rate ≤ <TODO: 5%> medido sobre golden Q&A set.
- **AC-006** Latency p95 (retrieval + rerank + generation) ≤ <TODO: NN s>.
- **AC-007** Citation: cada respuesta incluye top-K fuentes (k=3 default) con doc_id + chunk_id + relevance score.
- **AC-008** Refusal correcto si retrieval score top-1 < threshold (no inventar).

## 4. Corpus requirements

| Concern | Spec |
|---|---|
| Source(s) | <TODO: PDFs, Confluence, GitHub wikis, etc.> |
| Volume documents | <TODO: NN docs> |
| Volume tokens (post-chunk) | <TODO: NN M tokens> |
| Update frequency | <TODO: daily / weekly / on-demand> |
| Multilinguality | <TODO: ES, EN, ...> |
| PII (R2 trigger) | <TODO: si | no — si si, redaction antes de embed> |
| Access control | <TODO: per-tenant filtering, RBAC, scope:read> |
| Retention | <TODO: NN dias> |

## 5. Quality requirements

### 5.1 Performance

- Retrieval p95: <TODO: NN ms> (vector search)
- Rerank p95: <TODO: NN ms>
- Generation p95: <TODO: NN s> (LLM dependant)
- E2E p95: <TODO: NN s>
- Throughput: <TODO: NN queries/s>
- Cold start: <TODO: NN s> (embedding model load)

### 5.2 Security

- Input sanitization: prompt injection detection (Rebuff / NeMo Guardrails / regex).
- Output filtering: PII leak detector, toxicity classifier.
- Source whitelist: solo fuentes autorizadas.
- Rate limit per-tenant.

### 5.3 Compliance

- GDPR Art 22 (si decision automated): aplicable si | no.
- GDPR data minimization: solo embed lo necesario.
- EU AI Act Art 50 (transparency): user must know AI is involved + content labels.
- SOC 2: source attribution + audit log de queries.

### 5.4 Observability

- Retrieval metrics: hit rate, MRR, NDCG@10
- Generation metrics: faithfulness, relevance, citation accuracy (RAGAS async sample 1-5%)
- Cost per query: embed + retrieval + rerank + generation tokens
- LLM-as-judge runtime sampling (calibrated, multi-judge consensus para high-stakes)

## 6. Out of scope

- <TODO: e.g. multi-modal images / video>
- <TODO: e.g. user feedback fine-tuning>

## 7. References

- ADR linked: `docs/adr/<TODO: NNN-slug.md>`
- ARCA agents involucrados: `@rag-engineer`, `@ai-engineer`, `@math-critic`, `@trust-and-safety-engineer`, `@monitoring`
- Related skill: `langchain-rag`, `rag-systems`
