---
name: llm-engineering
description: Complete guide for LLM engineering including fine-tuning (LoRA, QLoRA, PEFT), structured outputs, guardrails, alignment (DPO, RLHF), prompt engineering, and production serving (vLLM). Use when working with LLM customization, adaptation, safety, or deployment tasks.
paths:
  - "**/llm/**"
  - "**/finetune*.py"
  - "**/*.ipynb"
---

# LLM Engineering

> **ARCA preference:** los bloques OpenAI (`gpt-4o`) y Gemini (`gemini-2.0-flash`) abajo muestran las APIs nativas de cada provider y se mantienen para el muestrario multi-provider. Dentro de ARCA usar siempre `claude-sonnet-4-6` (default) o `claude-opus-4-8` (high-stakes) vía la skill `anthropic-sdk`. Para frameworks neutrales como Instructor, el ejemplo default ya está actualizado a `anthropic/claude-sonnet-4-6`. Los bloques NeMo Guardrails / Guardrails AI mantienen su YAML/SDK shape canónico (con `engine: openai`) porque su esquema upstream lo exige.

## Stack 2025

| Component | Tools |
|-----------|-------|
| Fine-tuning | HuggingFace TRL, PEFT, bitsandbytes, Axolotl |
| Structured outputs | Instructor, Pydantic, native JSON mode |
| Guardrails | NeMo Guardrails, Guardrails AI, Llama Guard |
| Alignment | DPO (TRL), RLHF (PPO) |
| Serving | vLLM, TensorRT-LLM, Ollama |
| Tracking | W&B, MLflow, LangSmith |

---

## Fine-Tuning with PEFT

### When to Fine-Tune vs Prompt/RAG

| Approach | Use When |
|----------|----------|
| Prompting | Task is achievable with examples, no proprietary data |
| RAG | Need current/dynamic knowledge, citations required |
| Fine-tuning | Domain expertise, consistent style, latency-critical |

### LoRA Configuration

```python
from peft import LoraConfig, get_peft_model, TaskType
from transformers import AutoModelForCausalLM, BitsAndBytesConfig
import torch

# QLoRA: 4-bit quantization
bnb_config = BitsAndBytesConfig(
    load_in_4bit=True,
    bnb_4bit_quant_type="nf4",
    bnb_4bit_compute_dtype=torch.bfloat16,
    bnb_4bit_use_double_quant=True,
)

model = AutoModelForCausalLM.from_pretrained(
    "meta-llama/Llama-3.1-8B",
    quantization_config=bnb_config,
    device_map="auto",
    attn_implementation="flash_attention_2",
)

# LoRA config
lora_config = LoraConfig(
    r=16,                          # Rank: 8-64, higher = more capacity
    lora_alpha=32,                 # Scaling: typically 2x rank
    target_modules="all-linear",   # Or ["q_proj", "v_proj", "k_proj", "o_proj"]
    lora_dropout=0.05,
    bias="none",
    task_type=TaskType.CAUSAL_LM,
    # modules_to_save=["lm_head", "embed_tokens"],  # For chat templates
)

model = get_peft_model(model, lora_config)
model.print_trainable_parameters()  # Should be <1% of total
```

### Hyperparameters Guide

| Parameter | Recommended | Notes |
|-----------|-------------|-------|
| r (rank) | 8-32 | Higher for complex tasks, 16 is good default |
| lora_alpha | 2x rank | Controls adaptation strength |
| learning_rate | 1e-4 to 2e-4 | Lower for larger models |
| batch_size | 4-8 | With gradient accumulation |
| epochs | 1-3 | Monitor for overfitting |
| warmup_ratio | 0.03-0.1 | Stabilizes early training |

### Training with TRL SFTTrainer

```python
from trl import SFTTrainer, SFTConfig
from datasets import load_dataset

dataset = load_dataset("json", data_files="train.jsonl")

training_args = SFTConfig(
    output_dir="./output",
    num_train_epochs=1,
    per_device_train_batch_size=4,
    gradient_accumulation_steps=4,
    learning_rate=2e-4,
    lr_scheduler_type="cosine",
    warmup_ratio=0.03,
    logging_steps=10,
    save_strategy="epoch",
    bf16=True,
    gradient_checkpointing=True,
    max_seq_length=2048,
    packing=True,  # Efficient token packing
)

trainer = SFTTrainer(
    model=model,
    args=training_args,
    train_dataset=dataset["train"],
    processing_class=tokenizer,
    peft_config=lora_config,
)

trainer.train()

# Merge and save
model = model.merge_and_unload()
model.save_pretrained("./merged_model")
```

### VRAM Requirements

| Model Size | LoRA | QLoRA |
|------------|------|-------|
| 7B | ~16GB | ~6GB |
| 13B | ~32GB | ~10GB |
| 70B | ~160GB | ~40GB |

---

## Structured Outputs

### Native Provider Support (2025)

```python
# OpenAI
response = client.chat.completions.create(
    model="gpt-4o",
    response_format={"type": "json_schema", "json_schema": schema},
    messages=[...]
)

# Anthropic (beta)
response = client.beta.messages.create(
    model="claude-sonnet-4-6",
    betas=["structured-outputs-2025-11-13"],
    output_format={"type": "json_schema", "schema": schema},
    messages=[...]
)

# Gemini
response = genai.generate_content(
    model="gemini-2.0-flash",
    generation_config=genai.GenerationConfig(
        response_mime_type="application/json",
        response_schema=schema,
    ),
    contents=prompt
)
```

### Instructor (Universal)

```python
import instructor
from pydantic import BaseModel, Field
from typing import List

class Product(BaseModel):
    name: str = Field(description="Product name")
    price: float = Field(ge=0)
    features: List[str]

# Works with any provider — ARCA default below
client = instructor.from_provider("anthropic/claude-sonnet-4-6")
# client = instructor.from_provider("openai/gpt-4o")  # alternative provider
# client = instructor.from_provider("ollama/llama3.2")

product = client.chat.completions.create(
    response_model=Product,
    messages=[{"role": "user", "content": "iPhone 15: $999, A17 chip, titanium"}],
    max_retries=3,  # Auto-retry on validation failure
)
```

---

## Guardrails

### NeMo Guardrails (NVIDIA)

```yaml
# config.yml
models:
  - type: main
    engine: openai
    model: gpt-4

rails:
  input:
    flows:
      - self check input
  output:
    flows:
      - self check output

# Colang flows
define user ask about competitors
  "What about [competitor]?"
  "How does [competitor] compare?"

define bot refuse competitor discussion
  "I can only discuss our products. How can I help with those?"

define flow
  user ask about competitors
  bot refuse competitor discussion
```

```python
from nemoguardrails import RailsConfig, LLMRails

config = RailsConfig.from_path("./config")
rails = LLMRails(config)

response = rails.generate(
    messages=[{"role": "user", "content": "Tell me about competitor X"}]
)
```

### Guardrails AI (Validation)

```python
from guardrails import Guard
from guardrails.hub import ToxicLanguage, PIIFilter

guard = Guard().use_many(
    ToxicLanguage(on_fail="filter"),
    PIIFilter(on_fail="fix"),
)

result = guard(
    llm_api=openai.chat.completions.create,
    model="gpt-4o",
    messages=[{"role": "user", "content": prompt}],
)
```

### Common Rails

| Rail Type | Purpose |
|-----------|---------|
| Jailbreak detection | Block prompt injection attempts |
| Topic control | Keep conversations on-topic |
| PII detection | Filter personal information |
| Fact-checking | Verify claims against sources |
| Toxicity filter | Block harmful content |

---

## Alignment with DPO

### DPO vs RLHF

| Aspect | DPO | RLHF (PPO) |
|--------|-----|------------|
| Complexity | Simple classification loss | Reward model + RL |
| Stability | Very stable | Can be unstable |
| Compute | 1 model | 4 models (policy, ref, reward, value) |
| Performance | Comparable | Slightly better ceiling |

### DPO Training

```python
from trl import DPOTrainer, DPOConfig
from datasets import load_dataset

# Preference dataset format: prompt, chosen, rejected
dataset = load_dataset("argilla/ultrafeedback-binarized-preferences")

dpo_config = DPOConfig(
    output_dir="./dpo_output",
    num_train_epochs=1,
    per_device_train_batch_size=4,
    learning_rate=5e-7,
    beta=0.1,  # KL penalty weight (0.1-0.5)
    warmup_ratio=0.1,
    bf16=True,
    gradient_checkpointing=True,
)

trainer = DPOTrainer(
    model=model,
    ref_model=None,  # Uses model copy if None
    args=dpo_config,
    train_dataset=dataset["train"],
    processing_class=tokenizer,
    peft_config=lora_config,  # Can combine with LoRA
)

trainer.train()
```

### Creating Preference Data

| Method | Pros | Cons |
|--------|------|------|
| Human annotation | High quality | Expensive, slow |
| LLM-as-judge | Scalable, cheap | May have biases |
| Rule-based | Deterministic | Limited scope |
| AI feedback (RLAIF) | Best of both | Requires strong judge model |

---

## Production Serving with vLLM

### Why vLLM

- PagedAttention: 2-24x throughput vs naive serving
- Continuous batching: Dynamic request handling
- KV cache optimization: 60-80% memory savings
- OpenAI-compatible API

### Deployment

```bash
# Docker
docker run --gpus all -v ~/.cache/huggingface:/root/.cache/huggingface \
    -p 8000:8000 vllm/vllm-openai:latest \
    --model meta-llama/Llama-3.1-8B-Instruct \
    --tensor-parallel-size 1 \
    --max-model-len 8192

# Python
from vllm import LLM, SamplingParams

llm = LLM(
    model="meta-llama/Llama-3.1-8B-Instruct",
    tensor_parallel_size=1,
    gpu_memory_utilization=0.9,
    max_model_len=8192,
)

outputs = llm.generate(
    prompts=["Explain quantum computing"],
    sampling_params=SamplingParams(temperature=0.7, max_tokens=512),
)
```

### Scaling Options

| Parallelism | Use Case |
|-------------|----------|
| Tensor (TP) | Model too large for 1 GPU |
| Pipeline (PP) | Multi-node deployment |
| Data (DP) | Multiple model replicas |

### Production Checklist

- [ ] Quantization (AWQ/GPTQ) for memory efficiency
- [ ] Speculative decoding for latency
- [ ] KV cache sharing for multi-turn
- [ ] Prometheus metrics exposed
- [ ] Health check endpoint
- [ ] Rate limiting configured

---

## Anti-patterns

| [FAIL] Don't | [PASS] Do |
|----------|-------|
| Fine-tune without eval set | Hold out 10-20% for validation |
| Use high learning rate | Start with 1e-4, reduce if unstable |
| Train for many epochs | 1-3 epochs, watch for overfitting |
| Skip catastrophic forgetting check | Mix 20-30% general data |
| Deploy without guardrails | Always add input/output rails |
| Use full fine-tuning on large models | Use LoRA/QLoRA for efficiency |
