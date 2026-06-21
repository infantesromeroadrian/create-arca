---
description: Pipeline RAG completo desde diseño hasta evaluación. Uso: /rag-new <objetivo>
---
Construye pipeline RAG para: $ARGUMENTS

Arranca desde C4 (Design) del pipeline ML v4.0:
1. @token-optimizer → comprime contexto inicial
2. @skill-router → selecciona skills (rag-systems, langchain-rag, framework-selection)
3. @data-validator (BLOQUEANTE si hay corpus) → audita fuentes: duplicados, PII, leakage entre train/eval, cobertura por dominio
4. @architect-ai — diseño: chunking strategy, embeddings, vector store, reranking
5. @rag-engineer — implementación full pipeline
6. @prompt-engineer — diseño y versionado de prompts del generator (system + few-shot)
7. @math-critic — scoring functions (cosine, BM25, reciprocal rank fusion), estabilidad de embeddings
8. @model-evaluator — evaluación con RAGAS (faithfulness, answer_relevancy, context_precision/recall)
9. @cost-analyzer — coste por query (tokens + embeddings + vector store)
10. @code-critic — gate final antes de deploy

ADR obligatorio antes de BUILD. @data-validator bloqueante si hay corpus estructurado. @math-critic bloqueante antes de @code-critic.
