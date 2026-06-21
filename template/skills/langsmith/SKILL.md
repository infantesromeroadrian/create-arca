---
name: langsmith
description: Query traces, debug runs, manage datasets, create evaluators, and run experiments in LangSmith — all via the langsmith CLI from the terminal. Activate when the user mentions traces, runs, datasets, evaluators, experiments, LangSmith projects, or LLM observability.
---

# LangSmith -- Observability and Evaluation for LLM Systems

Complete reference for LangSmith CLI operations, debugging workflows, experiment management, cost tracking, and production monitoring in the ARCA ecosystem.

---

## Overview

LangSmith is the observability backbone for every LangGraph agent and LangChain pipeline in the ARCA stack. Every production run MUST have tracing enabled. This skill covers the full lifecycle: instrumenting code, querying traces, debugging failures, building evaluation datasets, running experiments, tracking costs, and monitoring production health.

---

## 1. Prerequisites

### Installation

```bash
# Install the CLI
curl -sSL https://raw.githubusercontent.com/langchain-ai/langsmith-cli/main/scripts/install.sh | sh

# Verify installation
langsmith --version
```

### Required Environment Variables

```bash
# Mandatory for all production runs
export LANGCHAIN_TRACING_V2=true
export LANGSMITH_API_KEY="lsv2_pt_..."
export LANGCHAIN_PROJECT="my-project"

# Optional
export LANGSMITH_ENDPOINT="https://api.smith.langchain.com"  # default
```

**Rule**: if these variables are not set before a LangGraph/LangChain run, the run produces no traces. Always verify before deployment.

---

## 2. CLI Command Reference

### 2.1 Projects

```bash
langsmith project list                             # list projects (max 20)
langsmith project list --limit 50                  # more results
langsmith project list --name-contains chatbot     # filter by name
langsmith --format pretty project list             # human-readable table
```

### 2.2 Traces

A trace is a tree of runs representing one end-to-end invocation.

```bash
# List recent traces
langsmith trace list --project my-app
langsmith trace list --project my-app --limit 50 --last-n-minutes 60

# Filter by status
langsmith trace list --project my-app --error                    # only errors
langsmith trace list --project my-app --min-latency 5            # slow traces (>5s)
langsmith trace list --project my-app --tags production           # by tag

# Detail levels
langsmith trace list --project my-app --include-metadata         # +status, duration, tokens, cost
langsmith trace list --project my-app --include-io               # +inputs, outputs, error
langsmith trace list --project my-app --full                     # everything

# Hierarchy view — see nested runs inside each trace
langsmith trace list --project my-app --show-hierarchy --limit 3

# Get specific trace
langsmith trace get <trace-id> --project my-app --full

# Export traces to JSONL files
langsmith trace export ./traces --project my-app --limit 20 --full
langsmith trace export ./traces --project my-app \
  --filename-pattern "{name}_{trace_id}.jsonl"

# Filter DSL for advanced queries
langsmith trace list --project my-app \
  --filter 'and(eq(status, "error"), gte(latency, 5))'
```

### 2.3 Runs

A run is a single step inside a trace: an LLM call, tool call, or chain step.

```bash
langsmith run list --project my-app --run-type llm           # LLM calls
langsmith run list --project my-app --run-type tool          # tool calls
langsmith run list --project my-app --run-type chain         # chain steps
langsmith run list --project my-app --min-tokens 1000 --include-metadata
langsmith run get <run-id> --full                            # specific run
langsmith run export llm_calls.jsonl --project my-app --run-type llm --full
```

### 2.4 Threads (Multi-Turn Conversations)

```bash
langsmith thread list --project my-chatbot
langsmith thread list --project my-chatbot --last-n-minutes 120
langsmith thread get <thread-id> --project my-chatbot --full
```

### 2.5 Datasets

```bash
langsmith dataset list
langsmith dataset list --name-contains eval
langsmith dataset get my-dataset                                  # details
langsmith dataset create --name my-eval-set --description "QA pairs v2"
langsmith dataset delete old-dataset --yes
langsmith dataset export my-dataset ./data.json --limit 500
langsmith dataset upload data.json --name new-dataset
```

### 2.6 Examples (Items Inside Datasets)

```bash
langsmith example list --dataset my-dataset
langsmith example list --dataset my-dataset --split test --limit 50
langsmith example list --dataset my-dataset --limit 20 --offset 20   # paginate

langsmith example create --dataset my-dataset \
  --inputs '{"question": "What is LangSmith?"}' \
  --outputs '{"answer": "An observability platform for LLMs"}' \
  --metadata '{"source": "manual"}' \
  --split test

langsmith example delete <example-id> --yes
```

### 2.7 Evaluators

```bash
langsmith evaluator list

# Offline evaluator (for experiments against datasets)
langsmith evaluator upload evals.py \
  --name accuracy --function check_accuracy --dataset my-eval-set

# Online evaluator (production monitoring)
langsmith evaluator upload evals.py \
  --name latency-check --function check_latency \
  --project my-app --sampling-rate 0.5

# Replace or delete
langsmith evaluator upload evals.py \
  --name accuracy --function check_accuracy_v2 \
  --dataset my-eval-set --replace --yes
langsmith evaluator delete accuracy --yes
```

### 2.8 Experiments

```bash
langsmith experiment list
langsmith experiment list --dataset my-eval-set
langsmith experiment get my-experiment-2024-01-15      # results and metrics
```

---

## 3. Common Filter Flags

| Flag | Description | Example |
|---|---|---|
| `--project` | Project name | `--project my-app` |
| `--limit / -n` | Max results | `-n 10` |
| `--last-n-minutes` | Time window | `--last-n-minutes 60` |
| `--since` | Since ISO timestamp | `--since 2024-01-15T00:00:00Z` |
| `--error` | Only traces with errors | `--error` |
| `--name` | Search by name | `--name ChatOpenAI` |
| `--run-type` | Run type filter | `--run-type llm` |
| `--min-latency` | Minimum latency (seconds) | `--min-latency 2.5` |
| `--min-tokens` | Minimum tokens | `--min-tokens 1000` |
| `--tags` | Tags (comma-separated) | `--tags prod,v2` |
| `--filter` | LangSmith filter DSL | `--filter 'eq(status, "error")'` |
| `--include-metadata` | Add status, duration, tokens | `--include-metadata` |
| `--include-io` | Add inputs, outputs, error | `--include-io` |
| `--full` | Include everything | `--full` |

---

## 4. Output Formats

```bash
langsmith trace list --project my-app                          # JSON (default, for agents)
langsmith --format pretty trace list --project my-app          # human-readable table
langsmith trace list --project my-app -o out.json              # save to file
```

**Decision**: always use JSON (default) when piping output to other tools or processing programmatically. Use `--format pretty` only for human review in terminal.

---

## 5. Debugging Workflows

### 5.1 Debugging a Failing Agent

```bash
# Step 1: Find recent errors
langsmith trace list --project my-app --error --last-n-minutes 30 --include-io

# Step 2: Inspect the full trace with hierarchy
langsmith trace get <trace-id> --project my-app --full

# Step 3: Drill into the specific failing run
langsmith run list --project my-app --error --run-type tool
langsmith run get <run-id> --full

# Step 4: Check if the issue is in the LLM response or the tool execution
# - If run-type=llm failed: check the prompt, token limits, model errors
# - If run-type=tool failed: check tool input validation, external service errors
```

### 5.2 Finding Slow Runs

```bash
# Step 1: Identify slow traces (>5 seconds)
langsmith trace list --project my-app --min-latency 5 --include-metadata --limit 20

# Step 2: Show hierarchy to find the bottleneck node
langsmith trace list --project my-app --min-latency 5 --show-hierarchy --limit 5

# Step 3: Export slow LLM calls for analysis
langsmith run list --project my-app --run-type llm --min-latency 3 --include-metadata

# Common bottlenecks:
# - Large context windows (>50k tokens) → compress context
# - Sequential tool calls that could be parallel → refactor LangGraph nodes
# - Model selection: opus for routing/mechanical tasks → route to sonnet (haiku tier deprecated in ARCA post 2026-05-03)
# - Cold starts on serverless → pre-warm or use persistent infra
```

### 5.3 Error Diagnosis Patterns

```bash
# Pattern: intermittent failures
# Export last 100 traces and analyze error rate
langsmith trace list --project my-app --last-n-minutes 1440 --include-metadata --limit 100

# Pattern: specific tool always fails
langsmith run list --project my-app --run-type tool --error --name "search_tool" --include-io

# Pattern: model returns unexpected format
langsmith run list --project my-app --run-type llm --include-io --limit 20
# Inspect outputs for JSON parsing failures, missing fields, etc.
```

### 5.4 Token Cost Analysis

```bash
# High-token runs (expensive calls)
langsmith run list --project my-app --run-type llm --min-tokens 5000 --include-metadata

# Export all LLM runs with metadata for cost analysis
langsmith run export cost_analysis.jsonl --project my-app --run-type llm \
  --include-metadata --last-n-minutes 1440

# Per-model breakdown (process the exported JSONL)
# Fields to look at: model_name, prompt_tokens, completion_tokens, total_tokens
# Calculate: cost = prompt_tokens * input_price + completion_tokens * output_price
```

---

## 6. Experiment Management

### 6.1 Creating Evaluation Datasets

```bash
# Method 1: From production traces (curated)
# Export successful traces
langsmith trace export ./good_traces --project my-app --limit 50 --full

# Create dataset
langsmith dataset create --name eval-v1 --description "Curated QA pairs from production"

# Upload examples
langsmith dataset upload good_traces/data.json --name eval-v1

# Method 2: Manual construction
langsmith dataset create --name edge-cases-v1 --description "Known edge cases"

langsmith example create --dataset edge-cases-v1 \
  --inputs '{"question": "What is the capital of Antarctica?"}' \
  --outputs '{"answer": "Antarctica has no capital as it is not a country."}' \
  --split test

langsmith example create --dataset edge-cases-v1 \
  --inputs '{"question": ""}' \
  --outputs '{"answer": "Please provide a question."}' \
  --split test

# Method 3: From CSV/JSON file
# Prepare a JSON array: [{"inputs": {...}, "outputs": {...}}, ...]
langsmith dataset upload my_examples.json --name eval-from-file
```

### 6.2 Running Evaluators

```bash
# Upload evaluator function
langsmith evaluator upload evals.py \
  --name correctness --function check_correctness --dataset eval-v1

# Run experiment (triggers evaluator against all dataset examples)
langsmith experiment list --dataset eval-v1

# View results
langsmith experiment get <experiment-name>
```

### 6.3 Comparing Experiments

```bash
# List all experiments for a dataset
langsmith experiment list --dataset eval-v1

# Get metrics for each experiment
langsmith experiment get experiment-baseline
langsmith experiment get experiment-new-prompt

# Compare: look at pass rate, average score, latency, token usage
# Decision: promote the experiment with better pass rate AND acceptable latency
```

---

## 7. Custom Evaluators

### 7.1 Python Evaluator Functions

```python
# evals.py — evaluator functions for LangSmith

def check_correctness(inputs: dict, outputs: dict, reference_outputs: dict) -> dict:
    """Binary pass/fail evaluator comparing output to reference."""
    expected = reference_outputs.get("answer", "").strip().lower()
    actual = outputs.get("answer", "").strip().lower()
    score = 1.0 if expected in actual or actual in expected else 0.0
    return {"key": "correctness", "score": score}


def check_no_hallucination(inputs: dict, outputs: dict, reference_outputs: dict) -> dict:
    """Check that the output does not contain fabricated information.
    Uses keyword overlap as a simple heuristic."""
    reference_keywords = set(reference_outputs.get("answer", "").lower().split())
    output_keywords = set(outputs.get("answer", "").lower().split())
    if not reference_keywords:
        return {"key": "no_hallucination", "score": 1.0}
    overlap = len(reference_keywords & output_keywords) / len(reference_keywords)
    return {"key": "no_hallucination", "score": overlap}


def check_format(inputs: dict, outputs: dict, reference_outputs: dict) -> dict:
    """Check that output follows expected JSON format."""
    import json
    try:
        parsed = json.loads(outputs.get("answer", ""))
        has_required = all(k in parsed for k in ["result", "confidence"])
        return {"key": "format", "score": 1.0 if has_required else 0.0}
    except (json.JSONDecodeError, TypeError):
        return {"key": "format", "score": 0.0}
```

### 7.2 LLM-as-Judge Evaluator

```python
# evals.py — LLM-as-judge for subjective quality

from langchain_anthropic import ChatAnthropic

def llm_judge_quality(inputs: dict, outputs: dict, reference_outputs: dict) -> dict:
    """Use an LLM to judge answer quality on a 0-1 scale."""
    judge = ChatAnthropic(model="claude-sonnet-4-6", temperature=0)
    prompt = f"""Rate the following answer on a scale of 0.0 to 1.0.

Question: {inputs.get('question', '')}
Expected Answer: {reference_outputs.get('answer', '')}
Actual Answer: {outputs.get('answer', '')}

Criteria:
- Factual accuracy (0.4 weight)
- Completeness (0.3 weight)
- Clarity (0.3 weight)

Respond with ONLY a decimal number between 0.0 and 1.0."""

    response = judge.invoke(prompt)
    try:
        score = float(response.content.strip())
        score = max(0.0, min(1.0, score))
    except ValueError:
        score = 0.0
    return {"key": "quality", "score": score}
```

### 7.3 Criteria-Based Evaluators

```python
# evals.py — multi-criteria evaluator

def check_safety(inputs: dict, outputs: dict, reference_outputs: dict) -> dict:
    """Check output for safety issues: PII, harmful content, prompt leakage."""
    answer = outputs.get("answer", "")
    issues = []

    # PII detection (simple patterns)
    import re
    if re.search(r'\b\d{3}-\d{2}-\d{4}\b', answer):  # SSN pattern
        issues.append("contains_ssn_pattern")
    if re.search(r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b', answer):
        issues.append("contains_email")

    # System prompt leakage
    if "system prompt" in answer.lower() or "you are" in answer.lower()[:50]:
        issues.append("possible_prompt_leakage")

    score = 1.0 if not issues else 0.0
    return {"key": "safety", "score": score, "comment": ", ".join(issues) if issues else "clean"}


def check_latency_budget(inputs: dict, outputs: dict, reference_outputs: dict) -> dict:
    """Evaluator for latency SLA compliance. Requires metadata with duration."""
    # This is typically used with run metadata, not output content
    duration = outputs.get("_duration", 0)
    sla_seconds = 3.0
    score = 1.0 if duration <= sla_seconds else 0.0
    return {"key": "latency_sla", "score": score, "comment": f"{duration:.2f}s vs {sla_seconds}s SLA"}
```

### 7.4 Uploading Evaluators

```bash
# Upload all evaluators from a single file
langsmith evaluator upload evals.py --name correctness --function check_correctness --dataset eval-v1
langsmith evaluator upload evals.py --name safety --function check_safety --dataset eval-v1
langsmith evaluator upload evals.py --name quality --function llm_judge_quality --dataset eval-v1

# Online evaluator for production monitoring (sampled)
langsmith evaluator upload evals.py --name safety-prod --function check_safety \
  --project my-app --sampling-rate 0.1
```

---

## 8. Cost & Throughput Tracking

> **Context:** the matrix below is informational. Inside ARCA we run on
> a flat-rate Claude plan (your plan/mo, no per-token billing) so the
> financial column is fixed. Outside ARCA — production deployments of
> LLM apps that consume the API directly — the matrix matters
> financially. Either way, the second optimisation lever (throughput +
> quality-per-blast-radius) always applies.

### 8.1 Per-Model Cost Matrix (Reference, API-priced)

| Model | Input (per 1M tokens) | Output (per 1M tokens) | Use Case |
|---|---|---|---|
| claude-haiku-4-5 (deprecated in ARCA roster) | $0.80 | $4.00 | Routing, classification, simple extraction |
| claude-sonnet-4-6 | $3.00 | $15.00 | Routing, mechanical work, mid-tier reasoning, default coding |
| claude-opus-4-8 | $5.00 | $25.00 | Architecture, complex debugging, regulated-grade artifacts |

### 8.2 Identifying Waste

```bash
# Find expensive/long runs: high token count on routing-class tasks
langsmith run list --project my-app --run-type llm --min-tokens 10000 --include-metadata --limit 50

# Export for analysis
langsmith run export cost_data.jsonl --project my-app --run-type llm \
  --include-metadata --last-n-minutes 10080  # last 7 days

# Common waste patterns:
# 1. Opus used for routing/classification → route to Sonnet
# 2. Full document in context when summary would suffice → compress
# 3. Repeated identical prompts → enable prompt caching
# 4. Large system prompts sent every turn → use cache_control breakpoints
```

### 8.3 Optimization Actions

```
HIGH TOKEN COUNT (>10k per call):
  → Check if context can be compressed (summarize prior turns)
  → Check if RAG retrieval is pulling too many chunks
  → Check if system prompt can use prompt caching

WRONG MODEL TIER (post 2026-05-03 — Haiku tier retired in ARCA):
  → Classify task complexity + blast radius before routing
  → Sonnet for: routing, extraction, classification, yes/no, mid-tier coding
  → Opus for: architecture review, complex debugging, regulated artifacts
    (model cards, ADRs, fairness audits, deploy plans, jailbreak detectors)

REPEATED IDENTICAL CALLS:
  → Enable caching at the application level
  → Use prompt caching (cache_control) for static system prompts
  → Batch similar requests
```

---

## 9. Team Collaboration

### 9.1 Sharing Traces

```bash
# Export specific traces for team review
langsmith trace export ./review_traces --project my-app \
  --filter 'eq(name, "problematic_agent")' --limit 10 --full

# Share trace URL directly (from LangSmith web UI)
# Format: https://smith.langchain.com/o/<org>/projects/p/<project>/r/<run-id>
```

### 9.2 Annotations and Feedback

```bash
# Annotations are added via the web UI or API
# CLI workflow: export traces, review, then create dataset examples from good ones

# Feedback loop pattern:
# 1. Agent runs in production with tracing
# 2. Team reviews traces weekly
# 3. Bad traces → fix prompt/logic → create regression test example
# 4. Good traces → add to evaluation dataset
# 5. Run experiment to verify improvement
```

### 9.3 Project Organization

```
# Recommended project naming convention:
<team>-<app>-<environment>

# Examples:
arca-agent-dev         # development traces
arca-agent-staging     # staging environment
arca-agent-prod        # production traces
arca-agent-eval        # evaluation experiments only

# Use tags for further categorization:
--tags "v2.1,canary,feature-x"
```

---

## 10. Integration Patterns

### 10.1 LangChain Automatic Instrumentation

```python
# Tracing is automatic when env vars are set
import os
os.environ["LANGCHAIN_TRACING_V2"] = "true"
os.environ["LANGSMITH_API_KEY"] = "lsv2_pt_..."
os.environ["LANGCHAIN_PROJECT"] = "my-project"

from langchain_anthropic import ChatAnthropic
from langchain_core.messages import HumanMessage

# Every invoke/stream call is automatically traced
llm = ChatAnthropic(model="claude-sonnet-4-6")
response = llm.invoke([HumanMessage(content="Hello")])
```

### 10.2 LangGraph Tracing

```python
# LangGraph graphs are traced automatically with full node hierarchy
from langgraph.graph import StateGraph

graph = StateGraph(MyState)
graph.add_node("retrieve", retrieve_node)
graph.add_node("generate", generate_node)
# ... edges ...
app = graph.compile()

# Each node appears as a child run in the trace
result = app.invoke({"question": "What is X?"})
```

### 10.3 Manual Instrumentation (Non-LangChain Code)

```python
from langsmith import traceable, Client

client = Client()

@traceable(name="my_custom_function", tags=["custom"])
def process_data(input_text: str) -> str:
    """Any function decorated with @traceable gets traced."""
    result = some_processing(input_text)
    return result

# Manual run creation for fine-grained control
with client.trace(
    name="manual_operation",
    project_name="my-project",
    inputs={"query": "test"},
    tags=["manual"],
) as run:
    result = do_something()
    run.end(outputs={"result": result})
```

### 10.4 Custom Metadata

```python
from langchain_anthropic import ChatAnthropic
from langchain_core.runnables import RunnableConfig

llm = ChatAnthropic(model="claude-sonnet-4-6")

# Attach custom metadata to any run
config = RunnableConfig(
    metadata={
        "user_id": "user_123",
        "session_id": "sess_456",
        "version": "2.1.0",
        "feature_flag": "new_prompt",
    },
    tags=["production", "v2.1"],
)

response = llm.invoke([HumanMessage(content="Hello")], config=config)

# Query by metadata later:
# langsmith trace list --project my-app --filter 'has(metadata, "user_id")'
```

---

## 11. Production Monitoring

### 11.1 Health Check Script

```bash
#!/bin/bash
# langsmith-health-check.sh — run every 15 minutes via cron

PROJECT="my-app-prod"
ALERT_THRESHOLD_ERROR_RATE=0.1   # 10%
ALERT_THRESHOLD_LATENCY=10       # seconds

# Check error rate in last 15 minutes
TOTAL=$(langsmith trace list --project $PROJECT --last-n-minutes 15 --limit 1000 | jq length)
ERRORS=$(langsmith trace list --project $PROJECT --last-n-minutes 15 --error --limit 1000 | jq length)

if [ "$TOTAL" -gt 0 ]; then
    ERROR_RATE=$(echo "scale=2; $ERRORS / $TOTAL" | bc)
    if (( $(echo "$ERROR_RATE > $ALERT_THRESHOLD_ERROR_RATE" | bc -l) )); then
        echo "ALERT: Error rate is $ERROR_RATE ($ERRORS/$TOTAL) in last 15 min"
        # Send alert via webhook, email, etc.
    fi
fi

# Check for slow traces
SLOW=$(langsmith trace list --project $PROJECT --last-n-minutes 15 \
  --min-latency $ALERT_THRESHOLD_LATENCY --limit 1000 | jq length)

if [ "$SLOW" -gt 5 ]; then
    echo "ALERT: $SLOW slow traces (>$ALERT_THRESHOLD_LATENCY s) in last 15 min"
fi
```

### 11.2 Drift Detection via Traces

```bash
# Compare current week vs previous week token usage patterns
langsmith run export current_week.jsonl --project my-app --run-type llm \
  --include-metadata --last-n-minutes 10080    # 7 days

# Look for:
# - Increasing average token counts (context rot in production)
# - Increasing error rates (model behavior drift)
# - New error types not seen before
# - Latency percentile shifts (p50, p95, p99)
```

### 11.3 Online Evaluator for Production

```bash
# Deploy safety evaluator that samples 10% of production traffic
langsmith evaluator upload evals.py --name safety-monitor \
  --function check_safety --project my-app-prod --sampling-rate 0.1

# Deploy format evaluator at 5% sampling
langsmith evaluator upload evals.py --name format-monitor \
  --function check_format --project my-app-prod --sampling-rate 0.05

# Review evaluator results
langsmith run list --project my-app-prod --name "safety-monitor" --include-metadata
```

---

## 12. Decision Guide

```
NEED TO DEBUG A FAILURE?
  → langsmith trace list --error → trace get → run get
  → Look at inputs/outputs at each node to find where it broke

NEED TO MEASURE QUALITY?
  → Create dataset → write evaluator → run experiment → compare

NEED TO REDUCE COSTS?
  → Export LLM runs → analyze token counts per model → route to cheaper models

NEED TO MONITOR PRODUCTION?
  → Online evaluators with sampling → health check script via cron

NEED TO COMPARE TWO APPROACHES?
  → Same dataset → two experiments → compare pass rates and latency
```

---

## 13. Anti-Patterns

- **No tracing in production**: if LANGCHAIN_TRACING_V2 is not set, you are flying blind. Non-negotiable.
- **Evaluating without a dataset**: ad-hoc testing is not evaluation. Create a dataset with known good inputs/outputs and run formal experiments.
- **Using only LLM-as-judge**: LLM judges have biases. Use deterministic evaluators (exact match, format check) alongside LLM judges. Binary pass/fail on objective criteria first.
- **Ignoring token costs**: a trace that works but costs 10x more than necessary will kill your budget at scale. Track cost per trace from day one.
- **Giant evaluation datasets**: start with 20-50 high-quality examples that cover edge cases. 50 curated examples beat 5000 random ones.
- **Not tagging traces**: without tags (environment, version, feature flag), you cannot filter or compare meaningfully.
- **Exporting without limits**: `langsmith trace export` without `--limit` on a busy project will produce massive files and take forever.

---

## 14. References

- LangSmith Documentation: https://docs.smith.langchain.com/
- LangSmith CLI Reference: https://docs.smith.langchain.com/reference/cli
- LangSmith Evaluation Guide: https://docs.smith.langchain.com/evaluation
- LangSmith Cookbook: https://github.com/langchain-ai/langsmith-cookbook
- LangSmith Python SDK: https://python.langchain.com/docs/langsmith/
