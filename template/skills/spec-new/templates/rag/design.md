---
feature: {{FEATURE}}
slug: {{SLUG}}
type: {{TYPE}}
created: {{DATE}}
status: Draft
related_adr: <TODO: ADR-NNN>
related_excalidraw: <TODO: docs/architecture/{{SLUG}}.excalidraw>
---

# Design — {{FEATURE}} (RAG system)

> Decisiones arquitecturales viven en `docs/adr/NNN-{{SLUG}}.md`.

## 1. Architecture summary

<TODO: 1 parrafo. Pipeline ingest → chunk → embed → index → retrieve → rerank → generate → cite.>

Reference: [ADR-NNN](../../adr/NNN-{{SLUG}}.md)
Diagrama: [{{SLUG}}.excalidraw](../../architecture/{{SLUG}}.excalidraw)

## 2. Components affected

| Component | Type | Action | Owner agent |
|---|---|---|---|
| `corpus/{{SLUG}}/` | Source docs | Ingest | `@data-engineer` |
| `pipelines/ingest_{{SLUG}}.py` | ETL chunking + embed | Create | `@rag-engineer` |
| `vector_store/{{SLUG}}/` | Index | Create | `@rag-engineer` |
| `services/rag_{{SLUG}}.py` | Retrieval + rerank + generation | Create | `@rag-engineer` |
| `evals/ragas_{{SLUG}}.py` | RAGAS eval suite | Create | `@rag-engineer` |
| `grafana/dashboards/rag_{{SLUG}}.json` | Quality + cost dashboard | Create | `@monitoring` |

## 3. Pipeline stages

### 3.1 Ingest

- Source: <TODO>
- Loader: <TODO: PyPDFLoader, ConfluenceLoader, GitHub API, etc.>
- Frequency: <TODO: cron schedule>

### 3.2 Chunking

- Strategy: <TODO: RecursiveCharacterTextSplitter | semantic | hierarchical | parent-document>
- Chunk size: <TODO: 512 tokens | 1024 chars>
- Overlap: <TODO: 50 tokens | 10%>
- Metadata: doc_id, chunk_id, source_url, timestamp, section, page (si PDF)

### 3.3 Embedding

| Concern | Choice | Justification |
|---|---|---|
| Model | <TODO: text-embedding-3-large | bge-large-en-v1.5 | e5-mistral-7b | local sentence-transformers> | <TODO: ADR ref> |
| Dimensions | <TODO: 1024 | 1536 | 3072> | <TODO> |
| Multilingual | <TODO: si | no> | <TODO> |
| Hosting | <TODO: Ollama local | OpenAI API | self-hosted vLLM> | <TODO> |

### 3.4 Vector store

| Concern | Choice | Justification |
|---|---|---|
| Backend | <TODO: Weaviate | Qdrant | ChromaDB | FAISS | pgvector> | <TODO> |
| Index type | <TODO: HNSW | IVF | flat> | <TODO: latency vs recall trade-off> |
| Hybrid retrieval | <TODO: dense + BM25 | dense only> | <TODO> |
| Filtering | <TODO: tenant_id, doc_type, lang> | <TODO> |

### 3.5 Retrieval

- Top-K initial: <TODO: 20>
- Score threshold: <TODO: cosine ≥ 0.7> (refusal si nadie pasa)
- Filtering: tenant scope + ACL

### 3.6 Reranking

- Model: <TODO: cross-encoder ms-marco | Cohere rerank | bge-reranker-large>
- Top-K final: <TODO: 5>
- Latency budget: <TODO: NN ms>

### 3.7 Generation

- LLM: <TODO: Claude Opus 4.8 | Sonnet 4.6 | Qwen 2.5 7B local | Mixtral 8x22B>
- Prompt template: structured con citations + refusal patterns
- Temperature: <TODO: 0.0 - 0.3> (deterministic para auditability)
- Max tokens: <TODO: 1500>
- Citation format: `[doc_id:chunk_id]` inline

## 4. Trade-offs

<TODO: linkear ADR.>

| Decision | Chosen | Alternatives rejected | Reason |
|---|---|---|---|
| Embedding hosted vs local | <TODO> | <TODO> | <TODO: cost / privacy / latency> |
| Hybrid vs dense only | <TODO> | <TODO> | <TODO: recall on rare queries> |
| Reranker yes/no | <TODO> | <TODO> | <TODO: latency vs precision> |

Detalle: [ADR-NNN](../../adr/NNN-{{SLUG}}.md).

## 5. Failure modes + mitigation

| Failure | Detection | Mitigation |
|---|---|---|
| Vector store unavailable | Health check | Circuit breaker → 503 + retry |
| Embedding API down | 5xx from provider | Fallback to local model |
| Context window overflow | Token count pre-call | Truncate oldest chunks o refuse |
| Hallucination | RAGAS faithfulness sample | Refusal + alert if rate > threshold |
| Prompt injection in retrieved docs (indirect) | Output classifier | Sanitize retrieved content + system prompt isolation |
| Citation mismatch (model cites doc not in context) | Post-generation regex check | Reject + retry o fallback |

## 6. Evaluation protocol

### 6.1 Golden Q&A set

- Volume: <TODO: ≥ 100 questions> curated por domain expert
- Diversity: easy / medium / hard / out-of-corpus (refusal expected)
- Update: monthly

### 6.2 RAGAS metrics

- Faithfulness (LLM-as-judge calibrated)
- Answer relevance
- Context precision
- Context recall
- Citation accuracy (custom)

### 6.3 Online eval

- Sample 1-5% production queries → RAGAS async
- LLM-as-judge multi-judge consensus para high-stakes
- User feedback (thumbs up/down)

## 7. Observability spec

### 7.1 Metrics

- `rag_retrieval_latency_seconds` histogram
- `rag_rerank_latency_seconds` histogram
- `rag_generation_latency_seconds` histogram
- `rag_e2e_latency_seconds` histogram
- `rag_hit_rate` gauge (top-K vs golden)
- `rag_faithfulness_score` gauge (sample)
- `rag_refusal_rate` gauge
- `rag_cost_per_query_usd` gauge

### 7.2 Dashboard (Grafana MCP)

Path: `grafana/dashboards/rag_{{SLUG}}.json`. Panels:
1. RED method E2E
2. Per-stage latency breakdown
3. RAGAS metrics trend
4. Hit rate top-K
5. Cost per query trend
6. Refusal rate (anomaly detection)

## 8. Security posture

- Prompt injection: Rebuff / NeMo Guardrails on input + indirect injection detection on retrieved docs
- Output: PII leak classifier, toxicity, jailbreak attempt detection
- Source whitelist enforced
- Rate limit per tenant
- Audit log: query + retrieved doc_ids + generated answer + citations (PII redacted)

## 9. Compliance

| Regulation | Article | Applicable | Evidence |
|---|---|---|---|
| GDPR | Art 22 | <TODO> | HITL si automated decision |
| EU AI Act | Art 50 | yes | "AI-generated answer" label |
| EU AI Act | Art 13 | yes | Transparency: user knows AI involved |
| SOC 2 | CC8.1 | yes | Audit trail completo |

## 10. Rollback plan

1. Disable feature flag para nuevos queries
2. Vector store snapshot restore (si index corrupted)
3. LLM model version pin previous
4. RTO: <TODO: NN min>

## 11. Open questions

- <TODO>
