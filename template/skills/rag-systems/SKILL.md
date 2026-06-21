---
name: rag-systems
description: "RAG framework-agnostic: chunking strategies, embeddings theory, hybrid search, reranking, RAGAS evaluation. Use for RAG design decisions and optimization. For LangChain-specific RAG code, use langchain-rag instead."
paths:
  - "**/rag/**"
  - "**/retrieval/**"
  - "**/embeddings/**"
  - "**/vectorstore*"
  - "**/chunk*"
effort: high
---

# RAG Systems - Best Practices 2025

## Principio Fundamental

```
"You can't have high-quality generation without high-quality retrieval,
and you can't have high-quality retrieval without intelligent chunking."
```

---

## RAG Architecture 2025

```
┌─────────────────────────────────────────────────────────────────────┐
│                      RAG Pipeline 2025                              │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐     │
│  │ Chunking │ -> │ Embedding│ -> │  Index   │ -> │  Store   │     │
│  └──────────┘    └──────────┘    └──────────┘    └──────────┘     │
│       ↑                                               ↓            │
│  Documents                                        Vector DB        │
│                                                                     │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐     │
│  │  Query   │ -> │  Hybrid  │ -> │ Rerank   │ -> │ Generate │     │
│  │ Rewrite  │    │  Search  │    │  Top-K   │    │   LLM    │     │
│  └──────────┘    └──────────┘    └──────────┘    └──────────┘     │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

## ¿Necesitas Chunking?

| Tipo de Documento | Chunking | Razón |
|-------------------|----------|-------|
| FAQs, tickets cortos | **NO** | Document-level mejor |
| Descripciones de productos | **NO** | Ya son unidades semánticas |
| Manuales, PDFs largos | **SÍ** | Esencial para retrieval preciso |
| Reportes financieros/legales | **SÍ** | Page-level recomendado |
| Código bien organizado | **Depende** | Evaluar grep vs RAG |

### Trade-off Fundamental
```
┌─────────────────────────────────────────────────────────────────┐
│ Chunks pequeños (100-256 tokens)                                │
│   ✓ Alta precisión en retrieval                                 │
│   ✓ Mejor matching semántico                                    │
│   ✗ Pierde contexto circundante                                 │
│   ✗ Fragmenta ideas completas                                   │
├─────────────────────────────────────────────────────────────────┤
│ Chunks grandes (1024+ tokens)                                   │
│   ✓ Preserva contexto completo                                  │
│   ✓ Mantiene relaciones entre ideas                             │
│   ✗ Retrieval menos preciso                                     │
│   ✗ Embeddings diluidos                                         │
└─────────────────────────────────────────────────────────────────┘
```

---

## Chunking Strategies

### 1. Fixed-Size (Simple, Rápido)
```python
from langchain.text_splitter import CharacterTextSplitter

splitter = CharacterTextSplitter(
    chunk_size=500,
    chunk_overlap=50,
    separator="\n"
)
chunks = splitter.split_text(document)
```
- **Pros**: Rápido, predecible, barato
- **Contras**: Ignora boundaries semánticos, corta oraciones
- **Usar para**: Prototipos, datos homogéneos

### 2. Recursive (Recomendado para Empezar)
```python
from langchain.text_splitter import RecursiveCharacterTextSplitter

splitter = RecursiveCharacterTextSplitter(
    chunk_size=500,
    chunk_overlap=50,  # 10-20% overlap
    separators=["\n\n", "\n", ". ", " ", ""],
    length_function=len,
)
chunks = splitter.split_documents(documents)
```
- **Pros**: Respeta estructura, balance calidad/velocidad
- **Contras**: No entiende semántica
- **Usar para**: La mayoría de aplicaciones RAG

### 3. Semantic Chunking (Alta Calidad)
```python
from langchain_experimental.text_splitter import SemanticChunker
from langchain_openai import OpenAIEmbeddings

embeddings = OpenAIEmbeddings()
splitter = SemanticChunker(
    embeddings=embeddings,
    breakpoint_threshold_type="percentile",  # o "standard_deviation"
    breakpoint_threshold_amount=95,  # threshold para split
)
chunks = splitter.split_documents(documents)
```
- **Pros**: Detecta cambios de tema, chunks coherentes
- **Contras**: Lento, costoso (requiere embeddings)
- **Usar para**: Documentos complejos, alta precisión requerida

### 4. Page-Level (Documentos Estructurados)
```python
from langchain_community.document_loaders import PyPDFLoader

loader = PyPDFLoader("document.pdf")
pages = loader.load_and_split()  # Cada página = 1 chunk

# O con metadata enriquecida
for i, page in enumerate(pages):
    page.metadata["page_number"] = i + 1
    page.metadata["source"] = "document.pdf"
```
- **NVIDIA 2024 Benchmark**: Highest accuracy (0.648) en docs con paginación significativa
- **Usar para**: Financial reports, legal docs, research papers

### 5. Hierarchical / Parent-Child
```python
from langchain.retrievers import ParentDocumentRetriever
from langchain.storage import InMemoryStore
from langchain_text_splitters import RecursiveCharacterTextSplitter

# Child splitter: chunks pequeños para retrieval preciso
child_splitter = RecursiveCharacterTextSplitter(chunk_size=200)

# Parent splitter: chunks grandes para contexto
parent_splitter = RecursiveCharacterTextSplitter(chunk_size=2000)

store = InMemoryStore()
retriever = ParentDocumentRetriever(
    vectorstore=vectorstore,
    docstore=store,
    child_splitter=child_splitter,
    parent_splitter=parent_splitter,
)
```
- **Beneficio**: Retrieval preciso + contexto completo
- **Usar para**: Cuando necesitas ambos

### Parámetros Recomendados 2025
```python
# Configuración balanceada (default recomendado)
CHUNK_SIZE = 400-512  # tokens
CHUNK_OVERLAP = 50-100  # 10-20%
TOP_K = 5  # chunks a recuperar

# Chroma Technical Report 2024:
# RecursiveCharacterTextSplitter(400 tokens) → 85-90% recall
# Sin overhead computacional de métodos semánticos
```

---

## Embedding Models 2025

### Leaderboard MTEB (Nov 2025)

| Rank | Modelo | MTEB Score | Dims | Costo/1M tokens | Mejor Para |
|------|--------|------------|------|-----------------|------------|
| 1 | Cohere embed-v4 | 65.2 | 1024 | $0.10 | Multilingual, Search |
| 2 | OpenAI text-embedding-3-large | 64.6 | 3072 | $0.13 | General purpose |
| 3 | Voyage AI voyage-3-large | 63.8 | 1536 | $0.12 | Domain tuning |
| 4 | BGE-M3 | 63.0 | 1024 | Free | Self-hosted |
| 5 | E5-Mistral-7B-Instruct | 61.8 | 4096 | Free | Open-source |
| 6 | Nomic-embed-text-v1.5 | 59.4 | 768 | $0.05 | Budget |
| 7 | all-MiniLM-L6-v2 | 56.3 | 384 | Free | Prototipado |
| 8 | OpenAI text-embedding-3-small | 55.8 | 1536 | $0.02 | Cost-effective |

### Selección por Caso de Uso

```python
# Startup/MVP (gratis, rápido)
from sentence_transformers import SentenceTransformer
model = SentenceTransformer('all-MiniLM-L6-v2')

# Producción (calidad)
from openai import OpenAI
client = OpenAI()
response = client.embeddings.create(
    model="text-embedding-3-large",
    input="Your text here",
    dimensions=1024,  # Reducir de 3072 para ahorrar storage
)

# Self-hosted (privacidad + calidad)
model = SentenceTransformer('BAAI/bge-large-en-v1.5')

# Multilingual
model = SentenceTransformer('BAAI/bge-m3')

# Code search
# Voyage code-2 o Nomic Embed Code
```

### Best Practices Embeddings

```python
import numpy as np

# 1. SIEMPRE normalizar para cosine similarity
embedding = embedding / np.linalg.norm(embedding)

# 2. MISMO modelo para indexing y query
# [FAIL] MALO: Indexar con model_A, query con model_B
# [PASS] BUENO: Mismo modelo siempre

# 3. Prefixes para instruction-tuned models (BGE, E5)
# Query
query = "query: What is machine learning?"
# Document
doc = "passage: Machine learning is a subset of AI..."

# 4. Dimensiones: balance accuracy vs storage
# 384-768: Prototipado, edge devices
# 1024: Production sweet spot
# 3072+: Máxima calidad, alto costo
```

---

## Vector Stores

### Selección por Escala

| Escala | Recomendación | Notas |
|--------|---------------|-------|
| Dev/POC (<10K docs) | Chroma, FAISS local | Gratis, simple |
| Producción (<1M docs) | Pinecone, Weaviate, Qdrant | Managed, escalable |
| Producción (>1M docs) | Pinecone, Milvus, Qdrant | Sharding, réplicas |
| On-premise/Privacidad | Qdrant, Milvus, pgvector | Self-hosted |

### Configuración por Herramienta

```python
# Chroma (desarrollo)
import chromadb
from chromadb.config import Settings

client = chromadb.Client(Settings(
    chroma_db_impl="duckdb+parquet",
    persist_directory="./chroma_db",
))
collection = client.create_collection(
    name="documents",
    metadata={"hnsw:space": "cosine"}
)

# FAISS (producción local, millones de vectores)
import faiss

# < 100K vectores: Flat index (exacto)
index = faiss.IndexFlatIP(dimension)

# > 100K vectores: HNSW (aproximado, rápido)
index = faiss.IndexHNSWFlat(dimension, 32)  # M=32
index.hnsw.efConstruction = 200  # Calidad construcción
index.hnsw.efSearch = 128  # Calidad búsqueda

# > 10M vectores: IVF-PQ (compresión)
quantizer = faiss.IndexFlatL2(dimension)
index = faiss.IndexIVFPQ(quantizer, dimension, nlist=1024, m=8, nbits=8)

# Pinecone (managed, producción)
from pinecone import Pinecone

pc = Pinecone(api_key="your-api-key")
index = pc.Index("my-index")
index.upsert(vectors=[
    {"id": "vec1", "values": embedding, "metadata": {"source": "doc1"}}
])
```

---

## Retrieval Optimization

### Hybrid Search (Dense + Sparse)

```python
# Combina BM25 (keyword) + Dense (semantic)
# Mejora significativamente tail recall

from langchain.retrievers import EnsembleRetriever
from langchain_community.retrievers import BM25Retriever

# BM25 para keyword matching
bm25_retriever = BM25Retriever.from_documents(documents)
bm25_retriever.k = 10

# Dense para semantic matching
dense_retriever = vectorstore.as_retriever(search_kwargs={"k": 10})

# Ensemble con Reciprocal Rank Fusion
ensemble = EnsembleRetriever(
    retrievers=[bm25_retriever, dense_retriever],
    weights=[0.3, 0.7],  # Ajustar según dominio
)

# Resultado: mejor cobertura de exact matches + semantic
```

**Cuándo usar Hybrid Search:**
- Vocabulario especializado (legal, médico, técnico)
- IDs, códigos, nombres propios
- Vanguard 2024: +12% retrieval accuracy con hybrid

### Re-ranking (CRÍTICO para Producción)

```python
# Stage 1: Retrieve top-50 con vector search (fast, high recall)
# Stage 2: Rerank a top-5 con cross-encoder (slow, high precision)

from sentence_transformers import CrossEncoder

# Cross-encoder reranking
reranker = CrossEncoder('cross-encoder/ms-marco-MiniLM-L-6-v2')

def rerank_results(query: str, documents: list, top_k: int = 5):
    """Rerank documents using cross-encoder."""
    pairs = [[query, doc.page_content] for doc in documents]
    scores = reranker.predict(pairs)
    
    # Sort by score descending
    ranked = sorted(zip(documents, scores), key=lambda x: x[1], reverse=True)
    return [doc for doc, score in ranked[:top_k]]

# Uso
initial_docs = retriever.get_relevant_documents(query)[:50]  # Fetch 50
final_docs = rerank_results(query, initial_docs, top_k=5)  # Keep 5

# Cohere Rerank (API, muy bueno)
import cohere
co = cohere.Client('api-key')
results = co.rerank(
    query=query,
    documents=[d.page_content for d in docs],
    top_n=5,
    model='rerank-english-v3.0'
)
```

**Benchmark Reranking 2025:**
- Pinecone: +48% mejora en retrieval quality
- ZeroEntropy zerank-1: +28% NDCG@10 improvement

### MMR (Maximal Marginal Relevance)

```python
# Evita redundancia en resultados
retriever = vectorstore.as_retriever(
    search_type="mmr",
    search_kwargs={
        "k": 5,  # Final results
        "fetch_k": 20,  # Candidates to consider
        "lambda_mult": 0.7,  # 0=max diversity, 1=max relevance
    }
)
```

### Query Expansion / Rewriting

```python
from langchain.retrievers.multi_query import MultiQueryRetriever

# Genera múltiples queries para mejor recall
multi_query_retriever = MultiQueryRetriever.from_llm(
    retriever=base_retriever,
    llm=llm,
)

# HyDE (Hypothetical Document Embeddings)
def hyde_retrieval(query: str, retriever, llm):
    """Generate hypothetical answer, then retrieve similar docs."""
    # Generar respuesta hipotética
    prompt = f"Write a detailed answer to: {query}"
    hypothetical = llm.invoke(prompt)
    
    # Usar respuesta hipotética para retrieval
    docs = retriever.get_relevant_documents(hypothetical.content)
    return docs
```

---

## Advanced Patterns

### Self-RAG (Auto-evaluación)

```python
def self_rag(query: str, retriever, llm):
    """RAG with self-evaluation of relevance."""
    docs = retriever.get_relevant_documents(query)
    
    # Evaluar relevancia de cada documento
    relevant_docs = []
    for doc in docs:
        eval_prompt = f"""
        Query: {query}
        Document: {doc.page_content}
        
        Is this document relevant to answer the query? (yes/no)
        """
        if "yes" in llm.invoke(eval_prompt).content.lower():
            relevant_docs.append(doc)
    
    # Generar respuesta solo con docs relevantes
    context = "\n".join([d.page_content for d in relevant_docs])
    return llm.invoke(f"Context: {context}\n\nQuestion: {query}")
```

### Corrective RAG (CRAG)

```python
def corrective_rag(query: str, retriever, llm):
    """Check if retrieval is sufficient, fallback to web if not."""
    docs = retriever.get_relevant_documents(query)
    
    # Evaluar si contexto es suficiente
    eval_prompt = f"""
    Query: {query}
    Retrieved context: {docs}
    
    Rate the relevance of the context (1-5):
    """
    score = int(llm.invoke(eval_prompt).content)
    
    if score < 3:
        # Contexto insuficiente → web search fallback
        web_docs = web_search(query)
        docs = docs + web_docs
    
    return generate_answer(query, docs, llm)
```

### GraphRAG (Knowledge Graph)

```python
# Para relaciones entre entidades
from langchain_community.graphs import Neo4jGraph

graph = Neo4jGraph(url="bolt://localhost:7687", username="neo4j", password="password")

# Extraer entidades y relaciones con LLM
# Construir grafo de conocimiento
# Retrieval: vector search + graph traversal
```

---

## RAG Chain Completo 2025

```python
from langchain_openai import ChatOpenAI, OpenAIEmbeddings
from langchain_community.vectorstores import Chroma
from langchain_core.prompts import ChatPromptTemplate
from langchain_core.runnables import RunnablePassthrough
from langchain_core.output_parsers import StrOutputParser

# 1. Setup
embeddings = OpenAIEmbeddings(model="text-embedding-3-small")
vectorstore = Chroma(
    persist_directory="./chroma_db",
    embedding_function=embeddings,
)

# 2. Retriever con MMR
retriever = vectorstore.as_retriever(
    search_type="mmr",
    search_kwargs={"k": 5, "fetch_k": 20},
)

# 3. Prompt optimizado
prompt = ChatPromptTemplate.from_template("""
You are a helpful assistant. Answer the question based ONLY on the provided context.
If the context doesn't contain enough information, say "I don't have enough information."

Context:
{context}

Question: {question}

Instructions:
- Be concise and direct
- Cite specific parts of the context when relevant
- If uncertain, acknowledge it
""")

# 4. Helper function
def format_docs(docs):
    return "\n\n---\n\n".join([
        f"Source: {doc.metadata.get('source', 'unknown')}\n{doc.page_content}"
        for doc in docs
    ])

# 5. Chain
from langchain_anthropic import ChatAnthropic
llm = ChatAnthropic(model="claude-sonnet-4-6", temperature=0)

rag_chain = (
    {"context": retriever | format_docs, "question": RunnablePassthrough()}
    | prompt
    | llm
    | StrOutputParser()
)

# 6. Invoke
response = rag_chain.invoke("What is machine learning?")
print(response)
```

---

## Evaluation (RAGAS Framework)

### Métricas Core

| Métrica | Qué Mide | Fórmula |
|---------|----------|---------|
| **Faithfulness** | Respuesta basada en contexto | claims_supported / total_claims |
| **Answer Relevancy** | Respuesta contesta la pregunta | semantic_similarity(answer, question) |
| **Context Recall** | Contexto contiene info necesaria | relevant_sentences / reference_sentences |
| **Context Precision** | Contexto bien rankeado | precision@k weighted by position |

### Implementación RAGAS

```python
from ragas import evaluate
from ragas.metrics import (
    Faithfulness,
    AnswerRelevancy,
    ContextRecall,
    ContextPrecision,
    FactualCorrectness,
)
from ragas.llms import LangchainLLMWrapper
from datasets import Dataset

# Preparar datos de evaluación
eval_data = {
    "user_input": ["What is ML?", "Explain RAG"],
    "response": ["ML is...", "RAG is..."],
    "retrieved_contexts": [["context1", "context2"], ["context3"]],
    "reference": ["ML is a subset of AI...", "RAG combines retrieval..."],  # Ground truth
}
dataset = Dataset.from_dict(eval_data)

# Evaluar
evaluator_llm = LangchainLLMWrapper(ChatAnthropic(model="claude-sonnet-4-6"))
result = evaluate(
    dataset=dataset,
    metrics=[
        Faithfulness(llm=evaluator_llm),
        AnswerRelevancy(llm=evaluator_llm),
        ContextRecall(llm=evaluator_llm),
        ContextPrecision(llm=evaluator_llm),
    ],
)

print(result)
# {'faithfulness': 0.85, 'answer_relevancy': 0.92, 
#  'context_recall': 0.78, 'context_precision': 0.88}
```

### Métricas de Retrieval Tradicionales

```python
from sklearn.metrics import ndcg_score
import numpy as np

def recall_at_k(retrieved_ids: list, relevant_ids: set, k: int) -> float:
    """Calculate Recall@K."""
    retrieved_k = set(retrieved_ids[:k])
    return len(retrieved_k & relevant_ids) / len(relevant_ids)

def mrr(retrieved_ids: list, relevant_ids: set) -> float:
    """Calculate Mean Reciprocal Rank."""
    for i, doc_id in enumerate(retrieved_ids):
        if doc_id in relevant_ids:
            return 1.0 / (i + 1)
    return 0.0

def precision_at_k(retrieved_ids: list, relevant_ids: set, k: int) -> float:
    """Calculate Precision@K."""
    retrieved_k = set(retrieved_ids[:k])
    return len(retrieved_k & relevant_ids) / k
```

### Evaluation Tools 2025

| Herramienta | Fortaleza | Uso |
|-------------|-----------|-----|
| RAGAS | Reference-free eval, métricas completas | RAG evaluation standard |
| DeepEval | Unit tests para LLMs, custom metrics | CI/CD integration |
| Arize Phoenix | Tracing + eval visual | Debugging, monitoring |
| LangSmith | Tracing + debugging LangChain | LangChain ecosistema |
| Giskard | Component-level breakdown | Identificar bottlenecks |

---

## Anti-patterns Comunes

```python
# [FAIL] MALO: Chunk size muy grande
splitter = RecursiveCharacterTextSplitter(chunk_size=2000)

# [PASS] BUENO: Chunk size balanceado
splitter = RecursiveCharacterTextSplitter(chunk_size=500, chunk_overlap=50)

# [FAIL] MALO: No re-ranking
docs = retriever.get_relevant_documents(query)[:5]

# [PASS] BUENO: Con re-ranking
docs = retriever.get_relevant_documents(query)[:50]
docs = reranker.rerank(query, docs)[:5]

# [FAIL] MALO: Solo dense retrieval
results = vectorstore.similarity_search(query)

# [PASS] BUENO: Hybrid search
results = ensemble_retriever.get_relevant_documents(query)

# [FAIL] MALO: Ignorar metadata
vectorstore.add_documents(docs)

# [PASS] BUENO: Metadata enriquecida
for doc in docs:
    doc.metadata.update({
        "source": source,
        "title": title,
        "date": date,
        "section": section,
    })
vectorstore.add_documents(docs)

# [FAIL] MALO: Diferentes modelos de embedding
# Indexar con model_A, query con model_B

# [PASS] BUENO: Mismo modelo siempre
embeddings = OpenAIEmbeddings(model="text-embedding-3-small")
# Usar para AMBOS: indexing y querying

# [FAIL] MALO: No evaluar
# "Parece que funciona bien"

# [PASS] BUENO: Métricas objetivas
result = evaluate(dataset, metrics=[Faithfulness(), ContextRecall()])
```

---

## Checklist RAG Production

### Pre-deployment
```
□ Chunking strategy evaluada con datos reales
□ Embedding model benchmarked (MTEB o domain-specific)
□ Retrieval metrics medidas (recall@5, MRR, nDCG)
□ Hybrid search si vocabulario especializado
□ Re-ranking implementado (cross-encoder o Cohere)
□ Metadata enriquecida en documentos
□ Ground truth dataset para evaluation
```

### Optimization
```
□ A/B test: dense-only vs hybrid vs hybrid+rerank
□ Chunk size tuning con métricas
□ Top-K optimization
□ Query expansion si queries ambiguas
□ MMR si redundancia en resultados
```

### Monitoring
```
□ Latencia de retrieval trackeada (target: <100ms)
□ Query logs para análisis
□ Feedback loop (thumbs up/down)
□ Alertas en degradación de métricas
□ Re-indexing schedule si datos cambian
```

---

## Performance Targets

| Métrica | Target | Acción si Bajo |
|---------|--------|----------------|
| Recall@5 | > 0.85 | Mejorar chunking, hybrid search |
| Context Precision | > 0.80 | Añadir re-ranking |
| Faithfulness | > 0.90 | Mejorar prompt, reducir contexto |
| Answer Relevancy | > 0.85 | Query rewriting, mejor retrieval |
| Latency (e2e) | < 2s | Optimizar índices, caching |
| Latency (retrieval) | < 100ms | HNSW tuning, hardware |

---

## Tools Stack 2025

| Función | Open Source | Managed |
|---------|-------------|---------|
| **Chunking** | LangChain, LlamaIndex | - |
| **Embeddings** | BGE, E5, Nomic | OpenAI, Cohere, Voyage |
| **Vector DB** | Chroma, FAISS, Qdrant | Pinecone, Weaviate |
| **Re-ranking** | Cross-encoders, ColBERT | Cohere Rerank |
| **Evaluation** | RAGAS, DeepEval | Arize, LangSmith |
| **Orchestration** | LangChain, LlamaIndex | - |

---

## Quick Reference

### Chunking Decision Tree
```
¿Documentos cortos (<500 tokens)?
  └─ SÍ → No chunking (document-level)
  └─ NO → ¿Documentos estructurados (PDF, papers)?
            └─ SÍ → Page-level chunking
            └─ NO → ¿Presupuesto para embeddings?
                      └─ SÍ → Semantic chunking
                      └─ NO → Recursive (400-512 tokens)
```

### Retrieval Pipeline Recomendado
```
1. Query Rewriting (opcional, si queries ambiguas)
2. Hybrid Search (BM25 + Dense)
3. Fetch top-50 candidates
4. Re-rank con cross-encoder
5. Return top-5 al LLM
```

### Embedding Selection
```
MVP/Prototipo: all-MiniLM-L6-v2 (gratis, rápido)
Producción: text-embedding-3-small (balance)
Alta calidad: Cohere embed-v4 o text-embedding-3-large
Self-hosted: BGE-M3 o E5-large
Código: Voyage code-2 o Nomic Embed Code
```
