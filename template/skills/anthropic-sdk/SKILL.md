---
name: anthropic-sdk
description: >-
  Anthropic Python SDK for Claude API. Messages API, vision, tool use, structured outputs,
  streaming, prompt caching, batch API, extended thinking, token counting, error handling,
  and model selection. Activate when building applications that call Claude directly via API,
  need structured JSON outputs, image analysis, tool orchestration, or batch processing.
upstream:
  package: anthropic
  language: python
  version_pin: "anthropic>=0.40.0"
  models_covered:
    - claude-opus-4-8
    - claude-sonnet-4-6
    - claude-haiku-4-5
  last_verified: "2026-05-03"
  source_of_truth: https://docs.anthropic.com/en/api/messages
  drift_check: |
    Re-verify when (a) >90 days since last_verified OR (b) Anthropic ships a new
    model in the 4.x family OR (c) a hot-path bug surfaces a stale field/endpoint.
    Procedure: re-read source_of_truth, diff against the SDK section examples in
    this SKILL.md, bump last_verified date, restate models_covered if needed.
---

> **Version-locked skill** (per docs/audit-policy.md whitelist 5 + skills/claude-code-patterns/SKILL.md "Patrón skills version-locked").
> The frontmatter `upstream` block declares which upstream version this skill
> documents and when it was last reconciled with the source of truth. Do not
> edit examples in the body without bumping `last_verified` after re-checking
> against the official Anthropic docs.

# Anthropic Python SDK — Complete Reference

## SDK Installation and Client Setup

```bash
pip install anthropic
# For async support (included by default, uses httpx)
pip install anthropic[bedrock]   # AWS Bedrock variant
pip install anthropic[vertex]    # Google Vertex variant
```

### Synchronous Client

```python
from anthropic import Anthropic

# Reads ANTHROPIC_API_KEY from environment by default
client = Anthropic()

# Explicit API key
client = Anthropic(api_key="sk-ant-...")

# Custom base URL (for proxies)
client = Anthropic(
    api_key="sk-ant-...",
    base_url="https://my-proxy.example.com/v1",
)

# With timeout and retries
client = Anthropic(
    timeout=60.0,        # seconds
    max_retries=3,       # default is 2
)
```

### Async Client

```python
from anthropic import AsyncAnthropic
import asyncio

client = AsyncAnthropic()

async def main():
    message = await client.messages.create(
        model="claude-sonnet-4-6",
        max_tokens=1024,
        messages=[{"role": "user", "content": "Explain quantum computing in 3 sentences."}],
    )
    print(message.content[0].text)

asyncio.run(main())
```

### Client for AWS Bedrock

```python
from anthropic import AnthropicBedrock

client = AnthropicBedrock(
    aws_region="us-east-1",
    # Uses default AWS credentials chain
)

message = client.messages.create(
    model="anthropic.claude-sonnet-4-6-20250514-v1:0",
    max_tokens=1024,
    messages=[{"role": "user", "content": "Hello from Bedrock."}],
)
```

### Client for Google Vertex AI

```python
from anthropic import AnthropicVertex

client = AnthropicVertex(
    project_id="my-gcp-project",
    region="us-east5",
)

message = client.messages.create(
    model="claude-sonnet-4-6@20250514",
    max_tokens=1024,
    messages=[{"role": "user", "content": "Hello from Vertex."}],
)
```

---

## Messages API — Core Usage

### Basic Completion

```python
from anthropic import Anthropic

client = Anthropic()

message = client.messages.create(
    model="claude-sonnet-4-6",
    max_tokens=1024,
    messages=[
        {"role": "user", "content": "What is the capital of France?"}
    ],
)

# Response structure
print(message.id)              # "msg_..."
print(message.model)           # "claude-sonnet-4-6-20250514"
print(message.role)            # "assistant"
print(message.content[0].text) # "The capital of France is Paris."
print(message.stop_reason)     # "end_turn" | "max_tokens" | "tool_use"
print(message.usage.input_tokens)   # 14
print(message.usage.output_tokens)  # 10
```

### System Prompts

```python
message = client.messages.create(
    model="claude-sonnet-4-6",
    max_tokens=1024,
    system="You are a senior Python architect. Respond with production-grade code only. No explanations unless asked.",
    messages=[
        {"role": "user", "content": "Write a retry decorator with exponential backoff."}
    ],
)
```

System prompt with multiple blocks (for prompt caching):

```python
message = client.messages.create(
    model="claude-sonnet-4-6",
    max_tokens=1024,
    system=[
        {
            "type": "text",
            "text": "You are a domain expert in distributed systems.",
        },
        {
            "type": "text",
            "text": "<reference_docs>...10,000 tokens of documentation...</reference_docs>",
            "cache_control": {"type": "ephemeral"},
        },
    ],
    messages=[
        {"role": "user", "content": "How does Raft consensus work?"}
    ],
)
```

### Multi-Turn Conversations

```python
messages = [
    {"role": "user", "content": "My name is ⟦ user_name ⟧."},
    {"role": "assistant", "content": "Nice to meet you, ⟦ user_name ⟧."},
    {"role": "user", "content": "What is my name?"},
]

message = client.messages.create(
    model="claude-sonnet-4-6",
    max_tokens=256,
    messages=messages,
)
# "Your name is ⟦ user_name ⟧."
```

Rule: messages must alternate user/assistant. First message must be user. Consecutive same-role messages are NOT allowed.

### Temperature and Top-P

```python
# Creative writing — high temperature
message = client.messages.create(
    model="claude-sonnet-4-6",
    max_tokens=2048,
    temperature=0.9,
    messages=[{"role": "user", "content": "Write a haiku about debugging."}],
)

# Deterministic extraction — temperature 0
message = client.messages.create(
    model="claude-sonnet-4-6",
    max_tokens=512,
    temperature=0.0,
    messages=[{"role": "user", "content": "Extract the dates from this text: ..."}],
)
```

### Stop Sequences

```python
message = client.messages.create(
    model="claude-sonnet-4-6",
    max_tokens=1024,
    stop_sequences=["```", "END"],
    messages=[{"role": "user", "content": "Generate Python code:"}],
)
# stop_reason will be "stop_sequence" if one is hit
```

---

## Vision — Image Analysis

### Base64 Image

```python
import base64
from pathlib import Path

image_data = base64.standard_b64encode(Path("screenshot.png").read_bytes()).decode("utf-8")

message = client.messages.create(
    model="claude-sonnet-4-6",
    max_tokens=1024,
    messages=[
        {
            "role": "user",
            "content": [
                {
                    "type": "image",
                    "source": {
                        "type": "base64",
                        "media_type": "image/png",
                        "data": image_data,
                    },
                },
                {
                    "type": "text",
                    "text": "Describe what you see in this screenshot.",
                },
            ],
        }
    ],
)
```

### URL Image

```python
message = client.messages.create(
    model="claude-sonnet-4-6",
    max_tokens=1024,
    messages=[
        {
            "role": "user",
            "content": [
                {
                    "type": "image",
                    "source": {
                        "type": "url",
                        "url": "https://example.com/diagram.png",
                    },
                },
                {
                    "type": "text",
                    "text": "Explain this architecture diagram.",
                },
            ],
        }
    ],
)
```

### Multi-Image Comparison

```python
message = client.messages.create(
    model="claude-sonnet-4-6",
    max_tokens=2048,
    messages=[
        {
            "role": "user",
            "content": [
                {
                    "type": "image",
                    "source": {"type": "base64", "media_type": "image/png", "data": before_b64},
                },
                {
                    "type": "image",
                    "source": {"type": "base64", "media_type": "image/png", "data": after_b64},
                },
                {
                    "type": "text",
                    "text": "Compare these two UI screenshots. What changed between before and after?",
                },
            ],
        }
    ],
)
```

### Vision Best Practices

| Guideline | Detail |
|-----------|--------|
| Supported formats | JPEG, PNG, GIF, WebP |
| Max image size | ~20MB per image |
| Token cost | Depends on resolution — smaller images cost fewer tokens |
| Resize first | Resize to the smallest resolution that preserves relevant detail |
| Place images before text | Image tokens are processed first; place text questions after |

---

## Tool Use (Function Calling)

### Defining Tools

```python
tools = [
    {
        "name": "get_weather",
        "description": "Get the current weather for a given location. Use when the user asks about weather conditions.",
        "input_schema": {
            "type": "object",
            "properties": {
                "location": {
                    "type": "string",
                    "description": "City and state/country, e.g. 'San Francisco, CA'",
                },
                "unit": {
                    "type": "string",
                    "enum": ["celsius", "fahrenheit"],
                    "description": "Temperature unit. Default: celsius.",
                },
            },
            "required": ["location"],
        },
    },
    {
        "name": "search_database",
        "description": "Search the internal product database by query string.",
        "input_schema": {
            "type": "object",
            "properties": {
                "query": {"type": "string", "description": "Search query."},
                "limit": {"type": "integer", "description": "Max results. Default: 10."},
            },
            "required": ["query"],
        },
    },
]
```

### Agentic Tool Loop

```python
import json

def execute_tool(name: str, input_data: dict) -> str:
    """Dispatch tool calls to actual implementations."""
    if name == "get_weather":
        # Real implementation here
        return json.dumps({"temp": 22, "condition": "sunny", "location": input_data["location"]})
    elif name == "search_database":
        return json.dumps({"results": [{"id": 1, "name": "Widget A"}]})
    else:
        return json.dumps({"error": f"Unknown tool: {name}"})


def run_agent(user_message: str) -> str:
    messages = [{"role": "user", "content": user_message}]

    while True:
        response = client.messages.create(
            model="claude-sonnet-4-6",
            max_tokens=4096,
            tools=tools,
            messages=messages,
        )

        # If no tool use, return the text response
        if response.stop_reason == "end_turn":
            return "".join(
                block.text for block in response.content if block.type == "text"
            )

        # Process tool calls
        tool_results = []
        for block in response.content:
            if block.type == "tool_use":
                result = execute_tool(block.name, block.input)
                tool_results.append(
                    {
                        "type": "tool_result",
                        "tool_use_id": block.id,
                        "content": result,
                    }
                )

        # Append assistant response and tool results
        messages.append({"role": "assistant", "content": response.content})
        messages.append({"role": "user", "content": tool_results})


# Usage
answer = run_agent("What's the weather in ⟦ timezone ⟧?")
```

### Parallel Tool Calls

Claude may return multiple `tool_use` blocks in a single response. Always iterate over all blocks:

```python
response = client.messages.create(
    model="claude-sonnet-4-6",
    max_tokens=4096,
    tools=tools,
    messages=[{"role": "user", "content": "Weather in ⟦ timezone ⟧ and Barcelona?"}],
)

# response.content might contain:
# [TextBlock("Let me check both..."), ToolUseBlock(get_weather, ⟦ timezone ⟧), ToolUseBlock(get_weather, Barcelona)]

tool_results = []
for block in response.content:
    if block.type == "tool_use":
        result = execute_tool(block.name, block.input)
        tool_results.append({
            "type": "tool_result",
            "tool_use_id": block.id,
            "content": result,
        })
```

### Forcing Tool Use

```python
# Force Claude to use a specific tool
response = client.messages.create(
    model="claude-sonnet-4-6",
    max_tokens=1024,
    tools=tools,
    tool_choice={"type": "tool", "name": "get_weather"},
    messages=[{"role": "user", "content": "⟦ timezone ⟧"}],
)

# Force Claude to use any tool (no plain text response)
response = client.messages.create(
    model="claude-sonnet-4-6",
    max_tokens=1024,
    tools=tools,
    tool_choice={"type": "any"},
    messages=[{"role": "user", "content": "Tell me about ⟦ timezone ⟧"}],
)

# Let Claude decide (default)
tool_choice = {"type": "auto"}
```

### Tool Use Error Handling

```python
# Return error as tool result — Claude will adapt
tool_results.append({
    "type": "tool_result",
    "tool_use_id": block.id,
    "content": json.dumps({"error": "API rate limited. Try again in 30s."}),
    "is_error": True,
})
```

---

## Structured Outputs via Tool Use

Force Claude to return structured JSON by defining a tool and requiring its use:

```python
from pydantic import BaseModel
import json


class ExtractedEntity(BaseModel):
    name: str
    entity_type: str  # "person" | "organization" | "location"
    confidence: float
    context: str


extraction_tool = {
    "name": "extract_entities",
    "description": "Extract named entities from text. Always use this tool to return results.",
    "input_schema": {
        "type": "object",
        "properties": {
            "entities": {
                "type": "array",
                "items": {
                    "type": "object",
                    "properties": {
                        "name": {"type": "string"},
                        "entity_type": {
                            "type": "string",
                            "enum": ["person", "organization", "location"],
                        },
                        "confidence": {"type": "number", "minimum": 0, "maximum": 1},
                        "context": {"type": "string"},
                    },
                    "required": ["name", "entity_type", "confidence", "context"],
                },
            }
        },
        "required": ["entities"],
    },
}

response = client.messages.create(
    model="claude-sonnet-4-6",
    max_tokens=1024,
    tools=[extraction_tool],
    tool_choice={"type": "tool", "name": "extract_entities"},
    messages=[
        {
            "role": "user",
            "content": "⟦ user_name ⟧ works at ARCA in ⟦ timezone ⟧.",
        }
    ],
)

# Parse the structured output
for block in response.content:
    if block.type == "tool_use":
        entities = [ExtractedEntity(**e) for e in block.input["entities"]]
        for entity in entities:
            print(f"{entity.name} ({entity.entity_type}): {entity.confidence:.0%}")
```

### Pydantic Schema Generation

```python
from pydantic import BaseModel, Field
from typing import Literal


class SentimentResult(BaseModel):
    sentiment: Literal["positive", "negative", "neutral"]
    score: float = Field(ge=-1, le=1, description="Sentiment score from -1 to 1")
    reasoning: str = Field(description="Brief explanation of sentiment classification")


# Convert Pydantic model to JSON Schema for the tool
sentiment_tool = {
    "name": "classify_sentiment",
    "description": "Classify the sentiment of the input text.",
    "input_schema": SentimentResult.model_json_schema(),
}

response = client.messages.create(
    model="claude-sonnet-4-6",
    max_tokens=512,
    tools=[sentiment_tool],
    tool_choice={"type": "tool", "name": "classify_sentiment"},
    messages=[{"role": "user", "content": "This product is absolutely terrible."}],
)

for block in response.content:
    if block.type == "tool_use":
        result = SentimentResult(**block.input)
        print(result)  # sentiment='negative' score=-0.9 reasoning='...'
```

---

## Streaming

### Basic Streaming

```python
with client.messages.stream(
    model="claude-sonnet-4-6",
    max_tokens=1024,
    messages=[{"role": "user", "content": "Write a short story about a robot."}],
) as stream:
    for text in stream.text_stream:
        print(text, end="", flush=True)

# Access final message after stream completes
final_message = stream.get_final_message()
print(f"\nTokens used: {final_message.usage.input_tokens} in, {final_message.usage.output_tokens} out")
```

### Event-Based Streaming

```python
with client.messages.stream(
    model="claude-sonnet-4-6",
    max_tokens=2048,
    messages=[{"role": "user", "content": "Explain recursion."}],
) as stream:
    for event in stream:
        if event.type == "content_block_start":
            print(f"[Block started: {event.content_block.type}]")
        elif event.type == "content_block_delta":
            if event.delta.type == "text_delta":
                print(event.delta.text, end="", flush=True)
        elif event.type == "message_stop":
            print("\n[Message complete]")
```

### Async Streaming

```python
from anthropic import AsyncAnthropic
import asyncio

async_client = AsyncAnthropic()

async def stream_response():
    async with async_client.messages.stream(
        model="claude-sonnet-4-6",
        max_tokens=1024,
        messages=[{"role": "user", "content": "List 10 design patterns."}],
    ) as stream:
        async for text in stream.text_stream:
            print(text, end="", flush=True)

asyncio.run(stream_response())
```

### Streaming with Tool Use

```python
with client.messages.stream(
    model="claude-sonnet-4-6",
    max_tokens=4096,
    tools=tools,
    messages=[{"role": "user", "content": "What's the weather in Tokyo?"}],
) as stream:
    for event in stream:
        if event.type == "content_block_start":
            if event.content_block.type == "tool_use":
                print(f"Calling tool: {event.content_block.name}")
        elif event.type == "content_block_delta":
            if event.delta.type == "text_delta":
                print(event.delta.text, end="", flush=True)
            elif event.delta.type == "input_json_delta":
                # Tool input arrives as partial JSON deltas
                print(event.delta.partial_json, end="")

    # After stream ends, process tool calls from final message
    final = stream.get_final_message()
```

---

## Prompt Caching

Prompt caching reduces costs by up to 90% on cached input tokens and reduces latency for repeated context.

### How It Works

- Mark content blocks with `cache_control: {"type": "ephemeral"}`
- Cached content persists for 5 minutes (TTL refreshed on hit)
- Minimum cacheable length: 1024 tokens (Haiku), 2048 tokens (Sonnet/Opus)
- Cache is per-model, per-organization

### Caching System Prompt

```python
response = client.messages.create(
    model="claude-sonnet-4-6",
    max_tokens=1024,
    system=[
        {
            "type": "text",
            "text": "You are a legal assistant specializing in EU regulations.",
        },
        {
            "type": "text",
            "text": "<eu_regulations>... (15,000 tokens of regulatory text) ...</eu_regulations>",
            "cache_control": {"type": "ephemeral"},
        },
    ],
    messages=[{"role": "user", "content": "What does GDPR Article 17 say?"}],
)

# Check cache usage
print(f"Cache creation tokens: {response.usage.cache_creation_input_tokens}")
print(f"Cache read tokens: {response.usage.cache_read_input_tokens}")
print(f"Uncached input tokens: {response.usage.input_tokens}")
```

### Caching Conversation History

```python
# Cache the long conversation prefix, vary only the last turn
messages = [
    # Old turns — cacheable
    {"role": "user", "content": "First question about the document..."},
    {"role": "assistant", "content": "Here's what I found..."},
    {"role": "user", "content": "Follow up question..."},
    {
        "role": "assistant",
        "content": [
            {
                "type": "text",
                "text": "Previous detailed answer...",
                "cache_control": {"type": "ephemeral"},  # Cache breakpoint HERE
            }
        ],
    },
    # New turn — not cached
    {"role": "user", "content": "New question about a different section."},
]

response = client.messages.create(
    model="claude-sonnet-4-6",
    max_tokens=1024,
    messages=messages,
)
```

### Caching Tools

```python
# Cache tool definitions (useful when sending many tools)
response = client.messages.create(
    model="claude-sonnet-4-6",
    max_tokens=1024,
    tools=[
        # ... first 19 tools ...
        {
            "name": "last_tool",
            "description": "...",
            "input_schema": {"type": "object", "properties": {}},
            "cache_control": {"type": "ephemeral"},  # Cache ALL tools up to here
        },
    ],
    messages=[{"role": "user", "content": "Help me with..."}],
)
```

### Cost Savings

| Token Type | Price Multiplier (vs base input) |
|------------|----------------------------------|
| Base input tokens | 1x |
| Cache write tokens | 1.25x |
| Cache read tokens | 0.1x (90% savings) |

Rule: cache pays off after ~2-3 requests with same prefix. For agentic loops with stable system prompt + tools, savings are massive.

---

## Batch API

Process large volumes asynchronously at 50% cost reduction.

### Creating a Batch

```python
import json

# Prepare requests
requests = []
for i, prompt in enumerate(prompts_list):
    requests.append({
        "custom_id": f"request-{i}",
        "params": {
            "model": "claude-sonnet-4-6",
            "max_tokens": 1024,
            "messages": [{"role": "user", "content": prompt}],
        },
    })

# Create batch
batch = client.batches.create(requests=requests)
print(f"Batch ID: {batch.id}")       # "batch_..."
print(f"Status: {batch.processing_status}")  # "in_progress"
```

### Polling for Completion

```python
import time

batch_id = batch.id

while True:
    batch = client.batches.retrieve(batch_id)
    print(f"Status: {batch.processing_status} "
          f"({batch.request_counts.succeeded}/{batch.request_counts.processing}/"
          f"{batch.request_counts.errored})")

    if batch.processing_status == "ended":
        break
    time.sleep(30)  # Poll every 30 seconds
```

### Retrieving Results

```python
# Stream results
results = []
for result in client.batches.results(batch_id):
    if result.result.type == "succeeded":
        text = result.result.message.content[0].text
        results.append({
            "id": result.custom_id,
            "text": text,
            "tokens": result.result.message.usage.output_tokens,
        })
    elif result.result.type == "errored":
        print(f"Error in {result.custom_id}: {result.result.error}")

print(f"Got {len(results)} successful results")
```

### Batch Best Practices

| Practice | Detail |
|----------|--------|
| Max requests | 100,000 per batch |
| Completion time | Up to 24 hours (usually much faster) |
| Cost | 50% discount vs synchronous API |
| Use cases | Evaluations, data labeling, bulk classification, migration |
| Idempotency | Use custom_id to match requests to results |

---

## Extended Thinking

Enable Claude's internal reasoning for complex tasks. The model produces thinking blocks before the final answer.

```python
response = client.messages.create(
    model="claude-opus-4-8",
    max_tokens=16000,
    thinking={
        "type": "enabled",
        "budget_tokens": 10000,  # Max tokens for thinking (must be < max_tokens)
    },
    messages=[
        {
            "role": "user",
            "content": "Prove that the square root of 2 is irrational.",
        }
    ],
)

# Response contains thinking blocks and text blocks
for block in response.content:
    if block.type == "thinking":
        print(f"[Thinking - {len(block.thinking)} chars]")
        print(block.thinking[:500])  # Preview thinking
    elif block.type == "text":
        print(f"\n[Answer]")
        print(block.text)
```

### Extended Thinking with Streaming

```python
with client.messages.stream(
    model="claude-opus-4-8",
    max_tokens=16000,
    thinking={"type": "enabled", "budget_tokens": 8000},
    messages=[{"role": "user", "content": "Design a distributed cache system."}],
) as stream:
    for event in stream:
        if event.type == "content_block_start":
            if event.content_block.type == "thinking":
                print("[Thinking...]", flush=True)
            elif event.content_block.type == "text":
                print("\n[Answer]", flush=True)
        elif event.type == "content_block_delta":
            if event.delta.type == "thinking_delta":
                print(event.delta.thinking, end="", flush=True)
            elif event.delta.type == "text_delta":
                print(event.delta.text, end="", flush=True)
```

### Extended Thinking Constraints

- `budget_tokens` must be less than `max_tokens`
- `temperature` must be 1 when thinking is enabled (cannot change)
- Thinking blocks are NOT cached between turns for multi-turn conversations
- Use `thinking` for math, coding, complex reasoning, architecture design
- Not needed for simple Q&A, classification, or extraction

### Extended Thinking in Multi-Turn

```python
# When continuing a conversation with thinking, pass thinking blocks back
messages = [
    {"role": "user", "content": "Solve this step by step: ..."},
]

response = client.messages.create(
    model="claude-opus-4-8",
    max_tokens=16000,
    thinking={"type": "enabled", "budget_tokens": 8000},
    messages=messages,
)

# For next turn, include the full assistant response (thinking + text)
messages.append({"role": "assistant", "content": response.content})
messages.append({"role": "user", "content": "Now extend that to handle edge cases."})

response2 = client.messages.create(
    model="claude-opus-4-8",
    max_tokens=16000,
    thinking={"type": "enabled", "budget_tokens": 8000},
    messages=messages,
)
```

---

## Token Counting

### Client-Side Token Counting

```python
# Count tokens before sending (avoids wasted API calls)
token_count = client.messages.count_tokens(
    model="claude-sonnet-4-6",
    system="You are a helpful assistant.",
    messages=[
        {"role": "user", "content": "Hello, how are you?"},
    ],
)
print(f"Input tokens: {token_count.input_tokens}")  # e.g., 22

# Count with tools
token_count = client.messages.count_tokens(
    model="claude-sonnet-4-6",
    tools=tools,
    messages=[
        {"role": "user", "content": "What's the weather?"},
    ],
)
print(f"Input tokens (with tools): {token_count.input_tokens}")
```

### Context Window Management

```python
MODEL_CONTEXT_WINDOWS = {
    "claude-opus-4-8": 200_000,
    "claude-sonnet-4-6": 200_000,
    "claude-haiku-4-5": 200_000,
}

MAX_OUTPUT_TOKENS = {
    "claude-opus-4-8": 32_000,
    "claude-sonnet-4-6": 16_000,
    "claude-haiku-4-5": 8_192,
}


def fits_in_context(model: str, messages: list, system: str = "") -> bool:
    count = client.messages.count_tokens(
        model=model,
        system=system,
        messages=messages,
    )
    max_input = MODEL_CONTEXT_WINDOWS[model] - MAX_OUTPUT_TOKENS[model]
    return count.input_tokens <= max_input
```

### Usage Tracking from Responses

```python
response = client.messages.create(
    model="claude-sonnet-4-6",
    max_tokens=1024,
    messages=[{"role": "user", "content": "Hello"}],
)

usage = response.usage
print(f"Input tokens: {usage.input_tokens}")
print(f"Output tokens: {usage.output_tokens}")

# With caching
if hasattr(usage, "cache_creation_input_tokens"):
    print(f"Cache creation: {usage.cache_creation_input_tokens}")
    print(f"Cache read: {usage.cache_read_input_tokens}")
```

---

## Error Handling

### Common Errors

```python
from anthropic import (
    Anthropic,
    APIError,
    APIConnectionError,
    RateLimitError,
    APIStatusError,
    AuthenticationError,
    BadRequestError,
    PermissionDeniedError,
    NotFoundError,
    InternalServerError,
)

client = Anthropic()

try:
    response = client.messages.create(
        model="claude-sonnet-4-6",
        max_tokens=1024,
        messages=[{"role": "user", "content": "Hello"}],
    )
except AuthenticationError:
    # 401 — invalid API key
    print("Invalid API key. Check ANTHROPIC_API_KEY.")
except BadRequestError as e:
    # 400 — malformed request (bad messages format, invalid model, etc.)
    print(f"Bad request: {e.message}")
except RateLimitError:
    # 429 — rate limited
    print("Rate limited. Back off and retry.")
except InternalServerError:
    # 500 — server error
    print("Anthropic server error. Retry with backoff.")
except APIStatusError as e:
    # 529 — overloaded
    if e.status_code == 529:
        print("API overloaded. Retry later.")
    else:
        print(f"API error {e.status_code}: {e.message}")
except APIConnectionError:
    # Network error
    print("Cannot connect to Anthropic API. Check network.")
```

### Retry with Exponential Backoff

The SDK has built-in retries (default: 2). For custom retry logic:

```python
import time
import random


def call_with_retry(
    client: Anthropic,
    max_retries: int = 5,
    base_delay: float = 1.0,
    **kwargs,
):
    """Call messages.create with exponential backoff and jitter."""
    for attempt in range(max_retries + 1):
        try:
            return client.messages.create(**kwargs)
        except RateLimitError:
            if attempt == max_retries:
                raise
            delay = base_delay * (2 ** attempt) + random.uniform(0, 1)
            print(f"Rate limited. Retrying in {delay:.1f}s (attempt {attempt + 1}/{max_retries})")
            time.sleep(delay)
        except InternalServerError:
            if attempt == max_retries:
                raise
            delay = base_delay * (2 ** attempt)
            time.sleep(delay)
        except APIStatusError as e:
            if e.status_code == 529:  # Overloaded
                if attempt == max_retries:
                    raise
                delay = base_delay * (2 ** attempt) + random.uniform(0, 2)
                time.sleep(delay)
            else:
                raise  # Non-retryable error
```

### SDK Built-in Retries

```python
# Configure retries at client level
client = Anthropic(
    max_retries=5,  # Default is 2
    timeout=120.0,  # Timeout in seconds
)

# Override per-request
response = client.messages.create(
    model="claude-sonnet-4-6",
    max_tokens=1024,
    messages=[{"role": "user", "content": "Hello"}],
    timeout=30.0,  # Per-request timeout override
)
```

---

## Model Selection Guide

### Model Comparison

| Model | ID | Best For | Context | Max Output | Speed |
|-------|-----|----------|---------|------------|-------|
| Opus 4.8 | `claude-opus-4-8` | Architecture, complex reasoning, research, regulated-grade artifacts | 200K | 32K | Slow |
| Sonnet 4.6 | `claude-sonnet-4-6` | Default. Routing, mechanical work, coding, analysis, writing | 200K | 16K | Fast |
| Haiku 4.5 | `claude-haiku-4-5` | High-volume API workloads where per-token cost dominates (deprecated in ARCA roster post 2026-05-03) | 200K | 8K | Fastest |

### Cost Matrix (per 1M tokens, approximate — API pricing)

| Model | Input | Output | Cache Write | Cache Read | Batch Input | Batch Output |
|-------|-------|--------|-------------|------------|-------------|-------------|
| Opus 4.8 | $15.00 | $75.00 | $18.75 | $1.50 | $7.50 | $37.50 |
| Sonnet 4.6 | $3.00 | $15.00 | $3.75 | $0.30 | $1.50 | $7.50 |
| Haiku 4.5 | $0.80 | $4.00 | $1.00 | $0.08 | $0.40 | $2.00 |

> Inside ARCA the team runs on a flat-rate Claude plan (your plan/mo, no
> per-token billing), so the matrix above is informational. When
> deploying applications that consume the Anthropic API directly, the
> matrix matters financially.

### ARCA Model Routing Strategy (post 2026-05-03)

```python
def select_model(task_type: str) -> str:
    """Route to optimal model based on task complexity + blast radius.

    The Haiku tier was retired from the ARCA roster in the 2026-05-03
    enterprise rewrite. Sonnet 4.6 absorbed routing/classification/
    extraction roles. The matrix below reflects the live ARCA roster.
    External applications calling the API directly may still use Haiku
    where per-token cost dominates and quality margin is comfortable.
    """
    routing = {
        # Opus 4.8 — regulated-grade, high blast radius
        "architecture_design": "claude-opus-4-8",
        "complex_debugging": "claude-opus-4-8",
        "code_review_critical": "claude-opus-4-8",
        "research_analysis": "claude-opus-4-8",
        "mathematical_proof": "claude-opus-4-8",
        "model_card_drafting": "claude-opus-4-8",
        "fairness_audit": "claude-opus-4-8",
        "deploy_plan_review": "claude-opus-4-8",
        "jailbreak_detection": "claude-opus-4-8",

        # Sonnet 4.6 — default workhorse + routing/mechanical
        "code_generation": "claude-sonnet-4-6",
        "code_review": "claude-sonnet-4-6",
        "documentation": "claude-sonnet-4-6",
        "data_analysis": "claude-sonnet-4-6",
        "general_qa": "claude-sonnet-4-6",
        "classification": "claude-sonnet-4-6",
        "extraction": "claude-sonnet-4-6",
        "routing": "claude-sonnet-4-6",
        "summarization_simple": "claude-sonnet-4-6",
        "input_validation": "claude-sonnet-4-6",
    }
    return routing.get(task_type, "claude-sonnet-4-6")


def select_model_external_api(task_type: str) -> str:
    """For per-token-billed deployments outside ARCA.

    Restores Haiku 4.5 for high-volume classification/extraction where
    the per-token-cost dominates and quality margin is comfortable.
    """
    routing = {
        "classification_high_volume": "claude-haiku-4-5",
        "extraction_high_volume": "claude-haiku-4-5",
        "input_validation_high_volume": "claude-haiku-4-5",
    }
    return routing.get(task_type, select_model(task_type))
```

---

## Best Practices

### System Prompt Design

```python
# GOOD: System prompt at top, clear role, constraints, format
message = client.messages.create(
    model="claude-sonnet-4-6",
    max_tokens=2048,
    system=(
        "You are a senior Python engineer. "
        "Rules:\n"
        "1. Use type hints on all functions\n"
        "2. Include docstrings (Google style)\n"
        "3. Handle errors explicitly — no bare except\n"
        "4. If the task is ambiguous, ask for clarification before writing code"
    ),
    messages=[{"role": "user", "content": "Write a connection pool manager."}],
)

# BAD: No system prompt, instructions mixed into user message
```

### Max Tokens Guidance

```python
# Always set max_tokens explicitly. The default varies by model.
# Set it based on expected output size, not just the maximum.

# Short answer / classification
max_tokens = 256

# Code generation / analysis
max_tokens = 4096

# Long document generation
max_tokens = 8192

# Extended thinking + answer
max_tokens = 16000  # budget_tokens must be less than this
```

### Message Alternation Rule

```python
# CORRECT: strict user/assistant alternation
messages = [
    {"role": "user", "content": "Hello"},
    {"role": "assistant", "content": "Hi there!"},
    {"role": "user", "content": "How are you?"},
]

# WRONG: consecutive same-role messages (will error)
messages = [
    {"role": "user", "content": "Hello"},
    {"role": "user", "content": "How are you?"},  # ERROR
]

# To combine multiple user inputs, use content blocks:
messages = [
    {
        "role": "user",
        "content": [
            {"type": "text", "text": "First part of my question."},
            {"type": "text", "text": "Second part of my question."},
        ],
    }
]
```

### Prefilling Assistant Responses

```python
# Guide output format by prefilling the assistant response
message = client.messages.create(
    model="claude-sonnet-4-6",
    max_tokens=1024,
    messages=[
        {"role": "user", "content": "Extract the JSON from this text: ..."},
        {"role": "assistant", "content": "{"},  # Force JSON output
    ],
)
# Response continues from "{"
full_json = "{" + message.content[0].text
```

---

## Decision Guide — When to Use What

| Need | Approach |
|------|----------|
| Simple Q&A | Basic messages.create with Sonnet |
| Image analysis | Vision with base64 or URL source |
| Structured data extraction | Tool use with forced tool_choice |
| Multi-step agent | Agentic tool loop with while + stop_reason check |
| Cost reduction on repeated context | Prompt caching with cache_control |
| Bulk processing (>100 requests) | Batch API at 50% discount |
| Complex reasoning / math | Extended thinking with Opus |
| Real-time UI | Streaming with text_stream |
| High-volume classification (per-token API) | Haiku 4.5 with low max_tokens |
| High-volume classification (ARCA / MAX flat-rate) | Sonnet 4.6 with low max_tokens |
| Production reliability | Built-in retries + custom exponential backoff |

---

## Anti-Patterns

| Anti-Pattern | Why It Fails | Fix |
|--------------|-------------|-----|
| Not setting max_tokens | Unpredictable costs, truncated responses | Always set explicitly per use case |
| Consecutive same-role messages | API error | Strict user/assistant alternation |
| Ignoring stop_reason | Missing tool calls, incomplete responses | Always check stop_reason in loops |
| Giant system prompt without caching | Repeated cost on every turn | Use cache_control on static content |
| Using Opus for classification | 5-20x API cost + 3x latency with no quality gain | Per-token API: use Haiku 4.5; under MAX flat-rate or in ARCA: use Sonnet 4.6 |
| Polling batch status every second | Wastes API quota, no speed gain | Poll every 30-60 seconds |
| Not handling 429/529 errors | Application crashes under load | Exponential backoff with jitter |
| Embedding full docs in every message | Context rot, token waste | Prompt caching or RAG |
| Using temperature=0 with extended thinking | API error | Temperature must be 1 with thinking |
| Skipping token counting | Surprise context window overflow | Count before sending, truncate if needed |

---

## References

- [Anthropic Python SDK](https://github.com/anthropics/anthropic-sdk-python)
- [API Reference](https://docs.anthropic.com/en/api/messages)
- [Prompt Caching](https://docs.anthropic.com/en/docs/build-with-claude/prompt-caching)
- [Tool Use](https://docs.anthropic.com/en/docs/build-with-claude/tool-use)
- [Vision](https://docs.anthropic.com/en/docs/build-with-claude/vision)
- [Extended Thinking](https://docs.anthropic.com/en/docs/build-with-claude/extended-thinking)
- [Batch API](https://docs.anthropic.com/en/docs/build-with-claude/batch-processing)
- [Model Comparison](https://docs.anthropic.com/en/docs/about-claude/models)
