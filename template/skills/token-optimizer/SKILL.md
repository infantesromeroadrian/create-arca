---
name: token-optimizer
description: Optimizador de tokens. Invoca PRIMERO en cualquier delegacion. Comprime contexto a ≤670 tokens, resume outputs antes de Engram a ≤200 tokens, y selecciona modelo correcto (sonnet por defecto para mechanical work, escala a opus solo si necesario).
model: sonnet
context: fork
effort: low
---

# Token Optimizer

Compresses context, selects the right model tier, and enforces token budgets across the ARCA delegation pipeline. This is the first agent invoked in every delegation and the last before saving to Engram.

---

## Overview

The token-optimizer serves two critical functions:

1. **Pre-delegation**: compress the task context to ≤670 tokens and recommend the model tier.
2. **Post-delegation**: compress the specialist's output to ≤200 tokens before saving to Engram.

**Why it exists**: uncompressed context degrades LLM performance. A 300-token focused prompt outperforms a 113k-token unfocused dump. Every token that enters a specialist's context must earn its place.

### Output Format

```json
{
  "summary": "Compressed task description (≤670 tokens for pre-delegation, <=150 for Engram)",
  "recommended_model": "sonnet|opus",
  "escalation_reason": "null if sonnet, otherwise why opus is needed",
  "token_count": 342,
  "compression_ratio": "4.2x"
}
```

---

## 1. Model Tier Selection

> **2026-05-03 enterprise rewrite note.** The Haiku tier was retired
> from the ARCA roster. Under a flat-rate Claude plan (your plan/mo, no
> per-token billing) the pricing pressure that motivated Haiku for
> routing disappeared, and Sonnet 4.6 absorbed those roles. Decision
> tree is now binary, not ternary. Cost matrix kept as informational —
> useful when the same code runs on a per-token API, not when running
> under MAX.

### Decision Tree (binary, post 2026-05-03)

```
Is the task ROUTING, CLASSIFICATION, MECHANICAL TRANSFORM, or
                MID-TIER REASONING?
  → SONNET 4.6 (claude-sonnet-4-6)

Is the task ARCHITECTURE REVIEW, COMPLEX DEBUGGING, NOVEL PROBLEM-SOLVING,
                REGULATED-GRADE OUTPUT (model card / ADR / fairness audit /
                jailbreak detector), or MULTI-STEP REASONING ACROSS
                SYSTEMS?
  → OPUS 4.8 (claude-opus-4-8)

UNSURE?
  → Start with SONNET. Escalate to OPUS only if sonnet output quality
    is insufficient OR the artifact has high blast radius if wrong.
```

### Cost Matrix (informational — per 1M tokens API pricing)

| Model | Input Cost | Output Cost | Context Window |
|---|---|---|---|
| claude-haiku-4-5 (deprecated in ARCA) | $0.80 | $4.00 | 200k |
| claude-sonnet-4-6 | $3.00 | $15.00 | 200k |
| claude-opus-4-8 | $5.00 | $25.00 | 200k |

> Under MAX flat-rate the marginal token is free. This matrix only
> matters when copying ARCA patterns into per-token API code (e.g.
> production deployment of LLM applications). Within ARCA, optimise
> for **throughput + quality**, not per-token cost.

### Routing Rules by Task Type

| Task Type | Model | Rationale |
|---|---|---|
| Skill routing | Sonnet | Pattern matching with light judgment |
| Token compression | Sonnet | Summarization of structured content |
| Code formatting / linting | Sonnet | Deterministic transformation with structural awareness |
| Code generation (single function) | Sonnet | Needs understanding of patterns |
| Code generation (system/module) | Opus | Multi-file reasoning, integration risk |
| RAG answer generation | Opus | Synthesis from retrieved context, regulated output |
| Bug diagnosis from traces | Opus | Analytical reasoning over data, blast radius |
| Architecture design / ADR writing | Opus | Novel synthesis, trade-off analysis |
| Complex multi-step debugging | Opus | Deep reasoning across code paths |
| Security audit / red teaming | Opus | Adversarial thinking, edge cases |
| Evaluation of model outputs | Opus | Calibrated criteria, regulated artifact |

### Escalation Triggers

Escalate from Sonnet to Opus when:
- Sonnet produces incorrect architecture recommendations.
- Debugging requires tracing through >3 abstraction layers.
- The task is explicitly flagged as critical (C10 Deploy review, security audit).
- The output is a regulated artifact (ADR, model card, fairness audit, deploy plan).

**Never escalate preemptively**. Try Sonnet first when the task allows.
Escalation is based on observed output quality + blast radius of the
artifact, not assumed difficulty.

---

## 2. Token Counting

### Estimating Before Sending

```python
# Quick estimation: 1 token ~ 4 characters (English), ~3.5 characters (code)
def estimate_tokens(text: str) -> int:
    """Rough estimate. Use tiktoken for precision."""
    return len(text) // 4

# Precise counting with tiktoken (for OpenAI-compatible models)
import tiktoken
enc = tiktoken.get_encoding("cl100k_base")
token_count = len(enc.encode(text))

# For Anthropic models, use the API's token counting endpoint
# or estimate: Anthropic tokenizer is ~5-10% different from cl100k_base
```

### Context Window Management

```
Total context: 200k tokens (all current Claude models)

Budget allocation per delegation:
  System prompt:     ~2,000 tokens (fixed)
  Skill content:     ~3,000 tokens (1-3 skills, ~1000 each)
  Task context:      ~500 tokens (compressed by token-optimizer)
  Conversation:      ~4,000 tokens (recent turns only)
  Tool outputs:      ~5,000 tokens (compressed, paths not content)
  ---
  Total working set: ~15,000 tokens

  Remaining for output: ~185,000 tokens
  (but aim for outputs <5,000 tokens — long outputs usually mean unfocused prompts)
```

### When Context Exceeds Budget

```
IF total context > 50,000 tokens:
  1. Compress tool outputs (replace content with file paths)
  2. Summarize conversation history (keep last 3 turns verbatim, summarize rest)
  3. Remove lowest-confidence skill

IF total context > 100,000 tokens:
  1. All of the above
  2. Isolate into sub-agent with fresh context (fork)
  3. Pass only the essential extracted facts, not full history

IF total context > 150,000 tokens:
  WARNING: CONTEXT ROT RISK
  Performance will degrade. Mandatory isolation into sub-agents.
```

---

## 3. Prompt Compression Techniques

### Technique 1: Structural Compression

Remove formatting noise while preserving information density.

```
BEFORE (87 tokens):
"The user is requesting that we build a new FastAPI endpoint that
accepts a POST request with a JSON body containing a 'query' field
and a 'context' field. The endpoint should call the LangGraph agent
with these inputs and return the result as a JSON response with
a 'result' field and a 'metadata' field."

AFTER (34 tokens):
"Build FastAPI POST endpoint. Input: {query, context} JSON.
Calls LangGraph agent. Returns: {result, metadata} JSON."

Compression ratio: 2.6x
Information loss: none
```

### Technique 2: Entity Extraction

Replace descriptions with references when the specialist already has domain knowledge.

```
BEFORE (120 tokens):
"We need to debug an issue in our LangGraph agent where the
retrieval node is using ChromaDB as the vector store and it's
returning documents that are not relevant to the user's query.
The embedding model is sentence-transformers/all-MiniLM-L6-v2
and the chunk size is 512 tokens with 50 token overlap."

AFTER (45 tokens):
"Debug: LangGraph retrieval node returns irrelevant docs.
Stack: ChromaDB + all-MiniLM-L6-v2, chunks=512/overlap=50.
Likely: embedding quality or chunk size issue."

Compression ratio: 2.7x
Information loss: none (specialist knows what ChromaDB and MiniLM are)
```

### Technique 3: Code Reference Compression

Never compress actual code. Instead, compress the description around it.

```
BEFORE:
"I wrote the following function to process the data and I think
there might be a bug on line 15 where the variable is not being
initialized properly before the loop starts:"
[50 lines of code]

AFTER:
"Bug suspected: line 15, uninitialized var before loop."
[50 lines of code — unchanged]

Rule: code is kept verbatim. Only the narrative around it is compressed.
```

### Technique 4: History Summarization

For multi-turn conversations, summarize older turns and keep recent turns verbatim.

```
BEFORE (conversation with 10 turns, ~3000 tokens):
Turn 1: User asked about X...
Turn 2: Assistant suggested Y...
...
Turn 10: User confirmed the approach.

AFTER (~800 tokens):
"Context: [turns 1-7 summary] Discussed X problem. Tried Y approach,
failed due to Z. Pivoted to W approach. User approved architecture."
[Turn 8 verbatim]
[Turn 9 verbatim]
[Turn 10 verbatim]

Rule: keep last 3 turns verbatim, summarize the rest.
```

---

## 4. Output Summarization for Engram

Before saving any specialist output to Engram, compress it to ≤200 tokens.

### Format

```
TOPIC: <domain/subtopic>
DECISION: <what was decided, 1 sentence>
CONTEXT: <why, constraints, trade-offs, 1-2 sentences>
ACTION: <what was done or needs to be done, 1 sentence>
FILES: <relevant file paths, if any>
```

### Examples

**Bad (280 tokens, too verbose)**:
```
We had a long discussion about whether to use ChromaDB or Weaviate
for the vector store in the RAG pipeline. ChromaDB is simpler and
works well for development but Weaviate has better production features
like multi-tenancy and hybrid search. We decided to use ChromaDB for
development and Weaviate for production. The configuration files are
in /config/vector_store.yaml and the abstraction layer is in
/src/retrieval/store.py. We also discussed using HNSW vs IVF indexes
and decided on HNSW for better recall at our dataset size (<1M docs).
```

**OK (120 tokens, compressed but missing key details)**:
```
Decided ChromaDB for dev, Weaviate for prod. Config in /config/.
Using HNSW indexes.
```

**Excellent (95 tokens, all critical information preserved)**:
```
TOPIC: rag/vector-store
DECISION: ChromaDB(dev) + Weaviate(prod) with abstraction layer
CONTEXT: Weaviate for multi-tenancy + hybrid search in prod. HNSW index chosen for <1M docs recall.
ACTION: Abstraction in /src/retrieval/store.py, config in /config/vector_store.yaml
```

### Rules for Engram Compression

1. **Always use the structured format** (TOPIC/DECISION/CONTEXT/ACTION/FILES).
2. **Preserve file paths** -- these are the most valuable for future context recovery.
3. **Preserve numbers and thresholds** -- "coverage >= 80%", "<1M docs", "latency < 200ms".
4. **Drop conversational fluff** -- "we discussed", "after consideration", "it was decided".
5. **Drop explanations of well-known concepts** -- the specialist reading from Engram already knows what HNSW is.
6. **Keep trade-off rationale** -- WHY a decision was made is more valuable than WHAT was decided.

---

## 5. History Management

### When to Include Prior Conversation

```
INCLUDE when:
  - The current task references a previous decision ("as we discussed")
  - The task builds on previous output (incremental development)
  - Debugging a previously working feature (need diff context)
  - User explicitly references earlier context

SKIP when:
  - New, independent task with no relation to prior work
  - The specialist agent is starting fresh (context: fork)
  - Prior conversation exceeds 10,000 tokens (summarize instead)
  - Task is a simple, self-contained operation (format code, run test)
```

### Conversation Pruning Strategy

```
Conversation length < 3,000 tokens:
  → Include everything

Conversation length 3,000 - 10,000 tokens:
  → Summarize turns 1 through N-3
  → Keep last 3 turns verbatim

Conversation length > 10,000 tokens:
  → Summarize all but last 2 turns
  → If still > 10,000: isolate into sub-agent with extracted facts only
```

---

## 6. Cost Analysis

### Per-Session Tracking

For each delegation session, track:

```
Session: <agent>/<task-id>
  Model: claude-sonnet-4-6
  Input tokens:  4,200
  Output tokens: 1,800
  Cost: $0.0396
  Duration: 3.2s
  Skills loaded: [langgraph, langsmith]
  Compression ratio: 3.1x (original task: 1,550 tokens → compressed: 500 tokens)
```

### Waste Identification Patterns

| Pattern | Signal | Fix |
|---|---|---|
| Opus for classification | Opus + output < 50 tokens | Route to Sonnet (Haiku tier deprecated post 2026-05-03) |
| Repeated context | Same system prompt sent 20x/session | Use prompt caching |
| Bloated tool outputs | Tool output > 5,000 tokens in message history | Write to file, pass path |
| Unused skills | Skill loaded but no content referenced in output | Improve routing accuracy |
| Re-asking for context | Specialist asks for information already in Engram | Check Engram before delegating |
| Long output with low info | Output > 3,000 tokens but 80% is boilerplate | Refine output format in prompt |

### Weekly Throughput Review Checklist (under MAX flat-rate)

```
1. Total invocations by model tier (sonnet / opus)
2. Top 5 longest sessions — were they justified or context rot?
3. Opus usage — could any have been sonnet without quality loss?
4. Average compression ratio at delegation handoff — is it above 2.5x?
5. Cache hit rate — are we using prompt caching effectively to keep
   ttfb low and reduce context rebuild overhead?
```

> Note: this is a quality/throughput review, not a billing review.
> Under a flat-rate Claude plan (your plan/mo) the financial cost is fixed.
> If copying these patterns into per-token API code, restore the
> financial dimension explicitly.

---

## 7. Prompt Caching

### When to Use cache_control

```
USE caching when:
  - System prompt > 1,000 tokens (amortize across calls)
  - Skill content loaded repeatedly by same agent type
  - Multi-turn conversation with stable prefix
  - Batch processing with identical instructions

DO NOT cache:
  - Dynamic content that changes every call
  - User input (always different)
  - Tool outputs (change per invocation)
```

### Breakpoint Placement

```python
# Correct: cache the static system prompt, not the dynamic user message
messages = [
    {
        "role": "system",
        "content": [
            {
                "type": "text",
                "text": SYSTEM_PROMPT,           # 2000 tokens, static
                "cache_control": {"type": "ephemeral"}  # cache this
            }
        ]
    },
    {
        "role": "system",
        "content": [
            {
                "type": "text",
                "text": SKILL_CONTENT,           # 1500 tokens, static per session
                "cache_control": {"type": "ephemeral"}  # cache this too
            }
        ]
    },
    {
        "role": "user",
        "content": compressed_task               # 500 tokens, dynamic — NOT cached
    }
]

# Cache savings: 3,500 tokens read from cache instead of re-processed
# On a 10-turn conversation: saves ~31,500 input tokens
```

### Cache Economics

```
Prompt caching pricing (Anthropic):
  Cache write:  1.25x base input price (one-time)
  Cache read:   0.10x base input price (every subsequent hit)
  Cache TTL:    5 minutes (resets on each hit)

Break-even: 2 hits on cached content = cheaper than no caching
  Write cost: 1.25x
  Read cost:  0.10x
  Total for 2 calls with cache: 1.25 + 0.10 = 1.35x
  Total for 2 calls without cache: 2.00x
  Savings start at call #2
```

---

## 8. Batch Optimization

### Grouping Similar Tasks

```
BEFORE (5 separate delegations):
  Task 1: "Add type hints to function A" → Sonnet call
  Task 2: "Add type hints to function B" → Sonnet call
  Task 3: "Add type hints to function C" → Sonnet call
  Task 4: "Add type hints to function D" → Sonnet call
  Task 5: "Add type hints to function E" → Sonnet call
  Total: 5 calls, 5x system prompt, 5x skill loading

AFTER (1 batched delegation):
  Task: "Add type hints to functions A, B, C, D, E"
  Total: 1 call, 1x system prompt, 1x skill loading
  Savings: ~80% fewer input tokens
```

### When to Batch

```
BATCH when:
  - Multiple tasks use the same specialist and skills
  - Tasks are independent (no dependency between them)
  - Combined context fits within budget (<15,000 tokens)
  - Tasks are similar in nature (same type of transformation)

DO NOT batch:
  - Tasks that depend on each other's output
  - Tasks requiring different model tiers
  - Tasks where failure of one should not block others
  - Tasks exceeding 10 items (quality degrades with too many)
```

---

## 9. Anti-Patterns

- **Compressing code**: never summarize, truncate, or alter code blocks. Code must be passed verbatim. Compress the narrative around the code instead.
- **Summarizing architecture decisions**: architecture rationale is high-value context. Compress the format (use TOPIC/DECISION/CONTEXT) but preserve ALL trade-off reasoning.
- **Using Opus for routing**: routing is pattern matching. Sonnet 4.6 handles it with sub-second latency and no quality loss. Opus for pure routing is throughput waste — Opus output tokens are ~3x slower to generate than Sonnet, and the routing decision rarely needs Opus-tier reasoning. (Pre 2026-05-03, this anti-pattern named Haiku as the right tier; the Haiku tier was retired in the enterprise rewrite.)
- **Skipping token estimation**: sending a 50,000-token tool output into a specialist's message history without checking its size first. Always estimate before appending.
- **Caching dynamic content**: putting cache_control on user messages or tool outputs that change every call. Only cache stable, repeated content.
- **Compressing to zero context**: over-compression that removes critical details (file paths, thresholds, error messages). The goal is density, not minimalism.
- **Not tracking compression ratios**: if you are not measuring, you cannot improve. Every compression should log its ratio.
- **Appending without compacting**: adding tool outputs to the message list without ever compressing old entries. This is the #1 cause of context rot in the ARCA pipeline.

---

## 10. Decision Guide

```
RECEIVING A NEW TASK?
  1. Estimate input tokens
  2. If > 500 tokens: compress using techniques 1-4
  3. Select model tier via decision tree
  4. Output: {summary, recommended_model, token_count}

SPECIALIST PRODUCED OUTPUT?
  1. Check if output needs to be saved to Engram
  2. If yes: compress to ≤200 tokens using Engram format
  3. Verify file paths and numbers are preserved
  4. Output: {summary, token_count}

CONTEXT GROWING DURING CONVERSATION?
  1. Monitor total context size after each turn
  2. At 50k tokens: compress tool outputs, summarize old turns
  3. At 100k tokens: fork to sub-agent with extracted facts
  4. At 150k tokens: CONTEXT ROT WARNING — mandatory isolation
```

---

## 11. References

- Anthropic prompt caching: https://docs.anthropic.com/en/docs/build-with-claude/prompt-caching
- Anthropic token counting: https://docs.anthropic.com/en/docs/build-with-claude/token-counting
- Context engineering principles: see @agent-ai-engineer skill
- ARCA delegation pipeline: see CLAUDE.md, "Orden de invocacion obligatorio"
- Model pricing: https://docs.anthropic.com/en/docs/about-claude/models
