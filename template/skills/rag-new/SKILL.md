---
name: rag-new
description: Pipeline RAG completo desde diseño hasta evaluación con RAGAS. Invócame cuando ⟦ user_name ⟧ diga quiero un RAG, nuevo pipeline RAG, retrieval augmented, /rag-new, o similar.
when_to_use: arranque de proyecto RAG (chunking + embeddings + retrieval + reranker + generator)
argument-hint: [objetivo-rag]
disable-model-invocation: false
user-invocable: true
allowed-tools: Read Grep Glob Bash(ls *) Bash(wc *) Write Edit
model: opus
effort: high
---

# /rag-new — pipeline RAG desde C4

⟦ user_name ⟧ pidió arrancar un pipeline RAG para: `$ARGUMENTS`

Arranca desde C4 (Design) del pipeline ML v4.0. Si no hay corpus aún, empezar por C2 (Data) del pipeline ML principal primero.

## Guardas de scope (preflight)

1. Si `$ARGUMENTS` está vacío → pide objetivo a ⟦ user_name ⟧ antes de iniciar.
2. Si hay corpus ya definido → @data-validator obligatorio antes de diseñar chunking.
3. Estimación de coste temprana (embeddings + vector store + tokens por query) antes de elegir stack.

## Pipeline (orden estricto)

1. @token-optimizer — comprime contexto inicial
2. @skill-router — selecciona skills (rag-systems, langchain-rag, framework-selection)
3. @data-validator (BLOQUEANTE si hay corpus) — audita fuentes: duplicados, PII, leakage entre train/eval, cobertura por dominio, balance idioma
4. @architect-ai — diseño: chunking strategy, embeddings, vector store, reranking strategy, ADR firmado
5. @rag-engineer — implementación full pipeline (ingestion, indexing, retrieval, reranker, generator prompt)
6. @prompt-engineer — diseño y versionado de prompts del generator (system + few-shot + guardrails)
7. @math-critic — scoring functions (cosine, BM25, reciprocal rank fusion), estabilidad de embeddings, métricas de retrieval
8. @model-evaluator — evaluación con RAGAS (faithfulness, answer_relevancy, context_precision/recall)
9. @cost-analyzer — coste por query (tokens + embeddings + vector store) + umbrales de alerta
10. @code-critic — gate final antes de deploy

## Reglas duras

- ADR obligatorio antes de BUILD (el rag-engineer no arranca sin firma de architect-ai).
- @data-validator bloqueante si hay corpus estructurado.
- @math-critic bloqueante antes de @code-critic.
- Si los scores RAGAS < baseline definido en spec → vuelve a C4 (rediseño), no parches en C8.

## Output esperado

- `docs/adr/rag-design.md` — decisión de stack
- `src/rag/` — pipeline modular (ingestion / retrieval / generation)
- `tests/test_rag_ragas.py` — evaluación reproducible
- Dashboard de métricas (faithfulness / context_precision / latencia p95)

**ultrathink** antes de aprobar la arquitectura RAG — chunking mal elegido se paga en todas las queries posteriores.
