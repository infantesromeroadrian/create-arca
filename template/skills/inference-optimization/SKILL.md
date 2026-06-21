---
name: inference-optimization
description: >-
  Model optimization for production inference: quantization (INT8, INT4, NF4, GPTQ, AWQ),
  ONNX export and optimization, TensorRT, profiling, hardware-specific tuning for ⟦ gpu ⟧.
  Use when optimizing inference latency, reducing model size, or deploying to GPU.
---

# Inference Optimization

## 1. Quantization Overview

### Why Quantize

Full-precision models (FP32) consume excessive memory and compute. Quantization reduces
numerical precision — from 32-bit floats down to 8-bit or 4-bit integers — shrinking model
size and accelerating inference. The core tradeoff is accuracy vs speed/memory.

| Precision | Bytes/Param | Relative Speed | Typical Accuracy Loss |
|-----------|-------------|----------------|-----------------------|
| FP32      | 4           | 1x (baseline)  | None                  |
| FP16/BF16 | 2           | ~1.5-2x        | Negligible            |
| INT8      | 1           | ~2-3x          | <1% on most tasks     |
| INT4/NF4  | 0.5         | ~3-4x          | 1-3%, task-dependent  |

**When to quantize:**
- Model does not fit in VRAM at full precision
- Latency SLA requires faster inference than FP16 can deliver
- Deploying to edge or cost-constrained environments
- Serving many concurrent requests under memory pressure

**When NOT to quantize:**
- Model already fits comfortably and meets latency targets
- Task is extremely sensitive to precision (e.g., medical scoring, financial modeling)
- You have not established a baseline evaluation yet (see Anti-patterns)

---

### 1.1 Post-Training Quantization (PTQ): INT8, INT4, NF4 with bitsandbytes

PTQ applies quantization after training is complete. No retraining required — fast to
apply, minimal infrastructure changes.

#### INT8 Quantization

Best starting point. Minimal accuracy degradation on most architectures.

```python
import torch
from transformers import AutoModelForCausalLM, AutoTokenizer, BitsAndBytesConfig

# INT8 quantization — minimal accuracy loss, ~50% memory reduction
quantization_config = BitsAndBytesConfig(
    load_in_8bit=True,
    llm_int8_threshold=6.0,          # outlier threshold
    llm_int8_has_fp16_weight=False,   # keep weights in INT8
)

model = AutoModelForCausalLM.from_pretrained(
    "meta-llama/Llama-3.1-8B",
    quantization_config=quantization_config,
    device_map="auto",
    torch_dtype=torch.float16,
)
tokenizer = AutoTokenizer.from_pretrained("meta-llama/Llama-3.1-8B")

# Verify memory usage
print(f"Model memory: {model.get_memory_footprint() / 1e9:.2f} GB")
```

#### INT4 / NF4 Quantization

Aggressive compression. NF4 (Normal Float 4-bit) is information-theoretically optimal
for normally-distributed weights, which most transformer weights approximate.

```python
from transformers import BitsAndBytesConfig

# NF4 quantization with double quantization for extra compression
quantization_config = BitsAndBytesConfig(
    load_in_4bit=True,
    bnb_4bit_quant_type="nf4",           # nf4 > fp4 for transformers
    bnb_4bit_compute_dtype=torch.bfloat16, # compute in bf16 (your GPU architecture supports it)
    bnb_4bit_use_double_quant=True,        # quantize the quantization constants
)

model = AutoModelForCausalLM.from_pretrained(
    "meta-llama/Llama-3.1-8B",
    quantization_config=quantization_config,
    device_map="auto",
)

# NF4 + double quant: ~4.2 bits/param effective → 8B model in ~4.5 GB VRAM
print(f"Model memory: {model.get_memory_footprint() / 1e9:.2f} GB")
```

**Key parameters:**
- `bnb_4bit_quant_type`: `"nf4"` for best quality, `"fp4"` for slightly faster quantization
- `bnb_4bit_compute_dtype`: `torch.bfloat16` on ⟦ gpu ⟧, `torch.float16` elsewhere
- `bnb_4bit_use_double_quant`: Saves ~0.4 bits/param at negligible cost

---

### 1.2 GPTQ: Grouped Quantization for LLMs

GPTQ performs layer-wise quantization using a calibration dataset to minimize output
reconstruction error. Produces static quantized weights — no runtime overhead from
dequantization during inference.

**Advantages over bitsandbytes:**
- Faster inference (weights are truly quantized, not dequantized on-the-fly)
- Better for serving (predictable latency)
- Supports grouped quantization (group_size=128 is standard)

**Disadvantages:**
- Requires calibration data (typically 128-256 samples)
- Quantization process is slow (hours for large models)
- Less flexible — fixed quantization after export

```python
from transformers import AutoModelForCausalLM, AutoTokenizer, GPTQConfig

# Prepare calibration dataset
tokenizer = AutoTokenizer.from_pretrained("meta-llama/Llama-3.1-8B")

calibration_texts = [
    "This is a sample calibration text for quantization.",
    # ... load 128-256 representative samples from your domain
]
calibration_data = [
    tokenizer(text, return_tensors="pt", max_length=512, truncation=True)
    for text in calibration_texts
]

# GPTQ config
gptq_config = GPTQConfig(
    bits=4,                    # 4-bit quantization
    group_size=128,            # group size for grouped quantization
    desc_act=True,             # activation ordering — slower but better quality
    dataset=calibration_data,  # calibration samples
    tokenizer=tokenizer,
    use_exllama=True,          # use ExLlama kernel for fast inference
)

# Quantize
model = AutoModelForCausalLM.from_pretrained(
    "meta-llama/Llama-3.1-8B",
    quantization_config=gptq_config,
    device_map="auto",
)

# Save quantized model
model.save_pretrained("./llama-8b-gptq-4bit")
tokenizer.save_pretrained("./llama-8b-gptq-4bit")
```

**Loading a pre-quantized GPTQ model:**

```python
from transformers import AutoModelForCausalLM, AutoTokenizer

model = AutoModelForCausalLM.from_pretrained(
    "TheBloke/Llama-2-7B-GPTQ",
    device_map="auto",
    torch_dtype=torch.float16,
)
# ExLlama kernel automatically used if available
```

---

### 1.3 AWQ: Activation-Aware Weight Quantization

AWQ identifies salient weight channels (those that correspond to large activations)
and protects them during quantization. This preserves model quality better than
uniform quantization at the same bit-width.

**When to prefer AWQ over GPTQ:**
- Slightly better perplexity than GPTQ at 4-bit on most benchmarks
- Faster quantization process than GPTQ
- Better support for fused attention kernels
- Recommended for LLM serving workloads

**When to prefer GPTQ over AWQ:**
- Wider ecosystem support and more pre-quantized models available
- ExLlama v2 kernel integration for maximum throughput
- Better tooling for custom calibration datasets

```python
from awq import AutoAWQForCausalLM
from transformers import AutoTokenizer

model_path = "meta-llama/Llama-3.1-8B"
quant_path = "./llama-8b-awq-4bit"

# Load model and tokenizer
model = AutoAWQForCausalLM.from_pretrained(model_path)
tokenizer = AutoTokenizer.from_pretrained(model_path)

# AWQ quantization config
quant_config = {
    "zero_point": True,       # use asymmetric quantization
    "q_group_size": 128,      # group size
    "w_bit": 4,               # 4-bit weights
    "version": "GEMM",        # GEMM kernel for RTX GPUs, GEMV for batch_size=1
}

# Quantize — uses calibration data internally
model.quantize(tokenizer, quant_config=quant_config)

# Save
model.save_quantized(quant_path)
tokenizer.save_pretrained(quant_path)
```

---

### 1.4 Quantization-Aware Training (QAT)

QAT simulates quantization during training, allowing the model to learn to compensate
for quantization error. Produces the highest-quality quantized models but requires
a training loop.

**When to use QAT:**
- Task accuracy is critical and PTQ degrades it unacceptably
- You have compute budget for fine-tuning
- Deploying INT8 models where even small accuracy drops matter

```python
import torch
from torch.quantization import prepare_qat, convert, get_default_qat_qconfig

# Example: QAT for a custom PyTorch model
model.train()
model.qconfig = get_default_qat_qconfig("x86")  # or "qnnpack" for ARM

# Fuse modules before QAT (Conv+BN+ReLU, Linear+ReLU, etc.)
torch.quantization.fuse_modules(model, [["conv1", "bn1", "relu"]], inplace=True)

# Insert fake quantization observers
model_prepared = prepare_qat(model)

# Fine-tune with fake quantization
optimizer = torch.optim.AdamW(model_prepared.parameters(), lr=1e-5)
for epoch in range(num_epochs):
    for batch in train_loader:
        outputs = model_prepared(batch["input_ids"])
        loss = criterion(outputs, batch["labels"])
        loss.backward()
        optimizer.step()
        optimizer.zero_grad()

# Convert to true quantized model
model_prepared.eval()
model_quantized = convert(model_prepared)

# Save
torch.save(model_quantized.state_dict(), "model_qat_int8.pt")
```

---

### 1.5 Quantization Decision Guide

```
START
  │
  ├─ Does the model fit in VRAM at FP16?
  │   ├─ YES → Is latency acceptable?
  │   │         ├─ YES → No quantization needed. Stop.
  │   │         └─ NO  → Try INT8 (bitsandbytes or GPTQ)
  │   └─ NO  → Go to aggressive compression
  │
  ├─ Aggressive compression needed:
  │   ├─ Serving workload (high throughput)?
  │   │   ├─ YES → AWQ 4-bit (GEMM kernel)
  │   │   └─ NO  → GPTQ 4-bit (ExLlama kernel)
  │   │
  │   ├─ Need QLoRA fine-tuning after quantization?
  │   │   └─ YES → NF4 via bitsandbytes
  │   │
  │   └─ Accuracy is paramount?
  │       └─ YES → QAT (requires training loop)
  │
  └─ ⟦ gpu ⟧ (your VRAM):
      ├─ Models ≤3B  → FP16 or INT8
      ├─ Models 7-8B → INT4/NF4 (fits ~4.5 GB)
      └─ Models >13B → Does not fit. Use offloading or smaller model.
```

---

## 2. ONNX Export and Optimization

### 2.1 Exporting PyTorch Models to ONNX

ONNX (Open Neural Network Exchange) provides a hardware-agnostic intermediate
representation. Export once, optimize for any backend.

```python
import torch
import torch.onnx

# Assume `model` is a trained PyTorch model in eval mode
model.eval()

# Create dummy input matching model's expected shape
dummy_input = torch.randn(1, 3, 224, 224, device="cuda")

# Export with dynamic axes for flexible batching
torch.onnx.export(
    model,
    dummy_input,
    "model.onnx",
    opset_version=17,
    input_names=["input"],
    output_names=["output"],
    dynamic_axes={
        "input": {0: "batch"},
        "output": {0: "batch"},
    },
    do_constant_folding=True,   # fold constant ops at export time
)

print("ONNX model exported to model.onnx")
```

**For transformer models, use optimum:**

```python
from optimum.onnxruntime import ORTModelForCausalLM

# Export HuggingFace model to ONNX automatically
model = ORTModelForCausalLM.from_pretrained(
    "meta-llama/Llama-3.1-8B",
    export=True,
)
model.save_pretrained("./llama-8b-onnx")
```

### 2.2 ONNX Runtime: Graph Optimizations and Operator Fusion

ONNX Runtime applies automatic graph optimizations: constant folding, redundant
node elimination, and operator fusion (e.g., MatMul+Add → Gemm, Conv+BN → Conv).

```python
import onnxruntime as ort
from onnxruntime.transformers import optimizer

# Optimize the ONNX graph
optimized_model = optimizer.optimize_model(
    "model.onnx",
    model_type="bert",          # or "gpt2", "vit", etc.
    num_heads=12,
    hidden_size=768,
    opt_level=2,                # 0=none, 1=basic, 2=extended (fusions)
)

# Enable mixed precision
optimized_model.convert_float_to_float16(
    use_symbolic_shape_infer=True,
    keep_io_types=True,         # keep inputs/outputs as FP32
)
optimized_model.save_model_to_file("model_optimized.onnx")
```

### 2.3 ONNX Runtime Execution Providers

```python
import onnxruntime as ort
import numpy as np

# CUDA Execution Provider — GPU inference
session = ort.InferenceSession(
    "model_optimized.onnx",
    providers=[
        ("CUDAExecutionProvider", {
            "device_id": 0,
            "arena_extend_strategy": "kNextPowerOfTwo",
            "gpu_mem_limit": 6 * 1024 * 1024 * 1024,  # 6GB limit for ⟦ gpu ⟧
            "cudnn_conv_algo_search": "EXHAUSTIVE",
        }),
        "CPUExecutionProvider",  # fallback
    ],
)

# TensorRT Execution Provider — highest performance on NVIDIA
session_trt = ort.InferenceSession(
    "model_optimized.onnx",
    providers=[
        ("TensorrtExecutionProvider", {
            "device_id": 0,
            "trt_max_workspace_size": 4 * 1024 * 1024 * 1024,  # 4GB
            "trt_fp16_enable": True,
            "trt_int8_enable": False,
            "trt_engine_cache_enable": True,
            "trt_engine_cache_path": "./trt_cache",
        }),
        ("CUDAExecutionProvider", {"device_id": 0}),
        "CPUExecutionProvider",
    ],
)

# Run inference
input_data = np.random.randn(1, 3, 224, 224).astype(np.float32)
outputs = session.run(None, {"input": input_data})
```

---

## 3. TensorRT

### 3.1 Conversion from ONNX

TensorRT builds an optimized inference engine from an ONNX graph, applying layer
fusion, kernel auto-tuning, precision calibration, and memory optimization specific
to the target GPU.

```bash
# Basic conversion: FP16 on ⟦ gpu ⟧
trtexec --onnx=model.onnx \
        --saveEngine=model.engine \
        --fp16 \
        --workspace=4096 \
        --verbose

# With dynamic shapes (variable batch size)
trtexec --onnx=model.onnx \
        --saveEngine=model_dynamic.engine \
        --fp16 \
        --minShapes=input:1x3x224x224 \
        --optShapes=input:4x3x224x224 \
        --maxShapes=input:16x3x224x224 \
        --workspace=4096
```

### 3.2 FP16 and INT8 Calibration

FP16 requires no calibration — direct conversion. INT8 requires a calibration dataset
to determine the dynamic range of activations at each layer.

```python
import tensorrt as trt
import pycuda.driver as cuda
import numpy as np

# INT8 calibration
class CalibrationDataset:
    def __init__(self, data_loader, batch_size=8):
        self.data_loader = data_loader
        self.batch_size = batch_size
        self.iterator = iter(data_loader)

    def get_batch(self):
        try:
            batch = next(self.iterator)
            return [batch.numpy()]
        except StopIteration:
            return None

class Int8Calibrator(trt.IInt8EntropyCalibrator2):
    def __init__(self, dataset, cache_file="calibration.cache"):
        super().__init__()
        self.dataset = dataset
        self.cache_file = cache_file
        self.device_input = cuda.mem_alloc(
            dataset.batch_size * 3 * 224 * 224 * 4  # FP32 input
        )

    def get_batch_size(self):
        return self.dataset.batch_size

    def get_batch(self, names):
        batch = self.dataset.get_batch()
        if batch is None:
            return None
        cuda.memcpy_htod(self.device_input, batch[0])
        return [int(self.device_input)]

    def read_calibration_cache(self):
        try:
            with open(self.cache_file, "rb") as f:
                return f.read()
        except FileNotFoundError:
            return None

    def write_calibration_cache(self, cache):
        with open(self.cache_file, "wb") as f:
            f.write(cache)
```

```bash
# INT8 with calibration cache
trtexec --onnx=model.onnx \
        --saveEngine=model_int8.engine \
        --int8 \
        --calib=calibration.cache \
        --workspace=4096
```

### 3.3 Dynamic Shapes and Batching

TensorRT supports optimization profiles for dynamic input dimensions. Define min,
optimal, and max shapes — TensorRT auto-tunes kernels for each profile.

```bash
# Multiple optimization profiles for different batch ranges
trtexec --onnx=model.onnx \
        --saveEngine=model_multi_profile.engine \
        --fp16 \
        --minShapes=input:1x3x224x224 \
        --optShapes=input:8x3x224x224 \
        --maxShapes=input:32x3x224x224 \
        --workspace=4096 \
        --buildOnly
```

### 3.4 When to Use TensorRT

| Scenario                          | Use TensorRT? | Why                                      |
|-----------------------------------|---------------|------------------------------------------|
| Production NVIDIA inference       | YES           | Maximum throughput and minimum latency    |
| Prototyping / experimentation     | NO            | Build time is long, iteration is slow     |
| Model changes frequently          | NO            | Must rebuild engine for every change      |
| Multi-GPU serving                 | MAYBE         | Use Triton Inference Server instead       |
| Non-NVIDIA deployment             | NO            | TensorRT is NVIDIA-only                   |
| Latency-critical real-time        | YES           | CUDA graphs + TRT = lowest latency        |

---

## 4. Profiling

### 4.1 PyTorch Profiler

```python
import torch
from torch.profiler import profile, record_function, ProfilerActivity, schedule

model.eval()
input_data = torch.randn(8, 3, 224, 224, device="cuda")

# Basic profiling: CPU + GPU time + memory
with profile(
    activities=[ProfilerActivity.CPU, ProfilerActivity.CUDA],
    record_shapes=True,
    profile_memory=True,
    with_stack=True,
) as prof:
    with record_function("inference"):
        with torch.no_grad():
            output = model(input_data)

# Print summary sorted by CUDA time
print(prof.key_averages().table(sort_by="cuda_time_total", row_limit=20))

# Export Chrome trace (open in chrome://tracing)
prof.export_chrome_trace("trace.json")

# Export for TensorBoard
prof.export_stacks("profiler_stacks.txt", "self_cuda_time_total")
```

**Scheduled profiling for training loops:**

```python
with profile(
    activities=[ProfilerActivity.CPU, ProfilerActivity.CUDA],
    schedule=schedule(
        wait=2,       # skip first 2 steps
        warmup=2,     # warmup for 2 steps (no recording)
        active=6,     # record 6 steps
        repeat=1,
    ),
    on_trace_ready=torch.profiler.tensorboard_trace_handler("./log/profiler"),
    record_shapes=True,
    profile_memory=True,
    with_stack=True,
) as prof:
    for step, batch in enumerate(data_loader):
        if step >= 10:
            break
        output = model(batch)
        loss = criterion(output, targets)
        loss.backward()
        optimizer.step()
        optimizer.zero_grad()
        prof.step()
```

### 4.2 NVIDIA Monitoring Tools

```bash
# Real-time GPU monitoring
nvidia-smi dmon -s pucvmet -d 1    # power, utilization, clocks, VRAM, memory, ECC, temp

# Detailed GPU info
nvidia-smi -q -d MEMORY,UTILIZATION,PERFORMANCE

# Continuous VRAM tracking (log to file)
nvidia-smi --query-gpu=timestamp,memory.used,memory.total,utilization.gpu \
           --format=csv -l 1 > gpu_log.csv

# nvtop — interactive GPU process monitor
nvtop
```

### 4.3 Latency Measurement: p50, p95, p99

```python
import time
import numpy as np
import torch

def measure_latency(
    model,
    input_data,
    num_warmup: int = 50,
    num_iterations: int = 500,
) -> dict:
    """Measure inference latency with proper warmup and CUDA sync."""
    model.eval()
    latencies = []

    with torch.no_grad():
        # Warmup — critical for accurate measurement
        for _ in range(num_warmup):
            _ = model(input_data)
        torch.cuda.synchronize()

        # Timed iterations
        for _ in range(num_iterations):
            torch.cuda.synchronize()
            start = time.perf_counter()
            _ = model(input_data)
            torch.cuda.synchronize()
            end = time.perf_counter()
            latencies.append((end - start) * 1000)  # ms

    latencies = np.array(latencies)
    return {
        "mean_ms": float(np.mean(latencies)),
        "std_ms": float(np.std(latencies)),
        "p50_ms": float(np.percentile(latencies, 50)),
        "p95_ms": float(np.percentile(latencies, 95)),
        "p99_ms": float(np.percentile(latencies, 99)),
        "min_ms": float(np.min(latencies)),
        "max_ms": float(np.max(latencies)),
        "throughput_qps": float(1000 / np.mean(latencies)),
    }

# Usage
input_data = torch.randn(1, 3, 224, 224, device="cuda")
stats = measure_latency(model, input_data)
print(f"p50: {stats['p50_ms']:.2f}ms | p95: {stats['p95_ms']:.2f}ms | p99: {stats['p99_ms']:.2f}ms")
print(f"Throughput: {stats['throughput_qps']:.1f} queries/sec")
```

### 4.4 Memory Profiling: Peak VRAM Tracking

```python
import torch

def measure_peak_memory(model, input_data, num_runs: int = 10) -> dict:
    """Track peak VRAM usage during inference."""
    model.eval()
    torch.cuda.reset_peak_memory_stats()
    torch.cuda.empty_cache()

    baseline_mem = torch.cuda.memory_allocated()

    with torch.no_grad():
        for _ in range(num_runs):
            _ = model(input_data)
            torch.cuda.synchronize()

    peak_mem = torch.cuda.max_memory_allocated()
    current_mem = torch.cuda.memory_allocated()

    return {
        "baseline_mb": baseline_mem / 1e6,
        "peak_mb": peak_mem / 1e6,
        "current_mb": current_mem / 1e6,
        "inference_overhead_mb": (peak_mem - baseline_mem) / 1e6,
        "peak_gb": peak_mem / 1e9,
        "vram_utilization_pct": (peak_mem / (8 * 1e9)) * 100,  # ⟦ gpu ⟧ = 8GB
    }

stats = measure_peak_memory(model, input_data)
print(f"Peak VRAM: {stats['peak_gb']:.2f} GB ({stats['vram_utilization_pct']:.1f}% of 8GB)")
```

---

## 5. ⟦ gpu ⟧ Specific Optimizations (your VRAM, )

### 5.1 Max Batch Sizes by Model Size

Estimated batch sizes at FP16, leaving ~1GB headroom for activations and system:

| Model Size | FP16 Weight Memory | Max Batch (FP16) | INT8 Batch | INT4/NF4 Batch |
|------------|-------------------|-------------------|------------|----------------|
| 125M       | ~250 MB           | 64+               | 128+       | 128+           |
| 350M       | ~700 MB           | 32                 | 64         | 128+           |
| 1.3B       | ~2.6 GB           | 8                  | 16         | 32             |
| 3B         | ~6 GB             | 1-2                | 4          | 8              |
| 7-8B       | ~16 GB (no fit)   | N/A (offload)      | N/A        | 1-2 (NF4)     |
| 13B+       | ~26 GB (no fit)   | N/A                | N/A        | N/A            |

**Rule of thumb for ⟦ gpu ⟧:**
- Comfortable: models up to 3B at FP16
- Tight: 7-8B at INT4/NF4 (leaves ~3.5 GB for KV cache and activations)
- Not feasible: 13B+ even at INT4 without CPU offloading

### 5.2 Flash Attention 2

⟦ gpu ⟧ fully supports Flash Attention 2, which provides O(N) memory
complexity instead of O(N^2) for self-attention.

```python
from transformers import AutoModelForCausalLM

# Enable Flash Attention 2
model = AutoModelForCausalLM.from_pretrained(
    "meta-llama/Llama-3.1-8B",
    torch_dtype=torch.bfloat16,
    attn_implementation="flash_attention_2",  # requires flash-attn>=2.0
    device_map="auto",
)

# Verify Flash Attention is active
print(model.config._attn_implementation)  # should print "flash_attention_2"
```

**Installation:**

```bash
# Flash Attention 2 — must match CUDA version
pip install flash-attn --no-build-isolation
```

**Impact on ⟦ gpu ⟧:**
- Sequence length 2048: ~30% less VRAM for attention
- Sequence length 4096: ~50% less VRAM for attention
- Sequence length 8192+: enables sequences that would otherwise OOM

### 5.3 torch.compile with max-autotune

`torch.compile` with the `max-autotune` backend benchmarks multiple CUDA kernel
implementations and selects the fastest for the target GPU.

```python
import torch

model.eval()

# Compile with max-autotune — slower first run, faster steady-state
compiled_model = torch.compile(
    model,
    mode="max-autotune",        # benchmarks triton kernels aggressively
    fullgraph=True,             # compile entire graph (no graph breaks)
    dynamic=False,              # static shapes for maximum optimization
)

# First call triggers compilation (can take minutes)
with torch.no_grad():
    dummy = torch.randn(1, 3, 224, 224, device="cuda")
    _ = compiled_model(dummy)   # warmup + compilation

# Subsequent calls use optimized kernels
output = compiled_model(input_data)
```

**Compilation modes:**

| Mode            | Compile Time | Runtime Speed | Use Case               |
|-----------------|-------------|---------------|------------------------|
| `default`       | Fast        | Good          | Development            |
| `reduce-overhead` | Medium   | Better        | Moderate latency needs |
| `max-autotune`  | Slow        | Best          | Production serving     |

### 5.4 CUDA Graphs for Inference

CUDA Graphs capture a sequence of GPU operations and replay them with minimal
CPU overhead. Eliminates kernel launch latency — critical for small models
where launch overhead dominates.

```python
import torch

model.eval()

# Static input — CUDA Graphs require fixed shapes
static_input = torch.randn(8, 3, 224, 224, device="cuda")
static_output = torch.empty(8, 1000, device="cuda")  # pre-allocate output

# Warmup
with torch.no_grad():
    for _ in range(3):
        static_output = model(static_input)
torch.cuda.synchronize()

# Capture CUDA graph
graph = torch.cuda.CUDAGraph()
with torch.cuda.graph(graph):
    static_output = model(static_input)

# Replay — fill input buffer, replay graph, read output
def infer_with_cuda_graph(new_input):
    static_input.copy_(new_input)
    graph.replay()
    torch.cuda.synchronize()
    return static_output.clone()

# Usage
result = infer_with_cuda_graph(torch.randn(8, 3, 224, 224, device="cuda"))
```

**Constraints:**
- Input/output shapes must be static (no dynamic batching)
- No CPU-dependent control flow inside the graph
- No memory allocations during replay
- Best combined with torch.compile for maximum effect

### 5.5 BF16 Support (⟦ gpu ⟧)

⟦ gpu ⟧ natively supports BF16 (Brain Float 16), which has the same dynamic
range as FP32 (8 exponent bits) with reduced precision (7 mantissa bits vs 23).
Prefer BF16 over FP16 for training stability and when mixing with quantization.

```python
# BF16 inference — no loss scaling needed (unlike FP16)
model = model.to(dtype=torch.bfloat16, device="cuda")

with torch.no_grad(), torch.autocast(device_type="cuda", dtype=torch.bfloat16):
    output = model(input_data)
```

---

## 6. Batching Strategies

### Static Batching

Fixed batch size, all requests padded to the same length. Simple but wasteful.

```python
# Pad all inputs to max_length
batch = tokenizer(
    texts,
    padding="max_length",
    max_length=512,
    truncation=True,
    return_tensors="pt",
).to("cuda")
```

### Dynamic Batching

Group requests by similar length, pad to the longest in each batch. Reduces
wasted compute on padding tokens.

```python
from torch.utils.data import DataLoader

def collate_dynamic(batch):
    """Pad to max length in batch, not global max."""
    texts = [item["text"] for item in batch]
    return tokenizer(
        texts,
        padding="longest",         # pad to longest in this batch
        truncation=True,
        max_length=2048,
        return_tensors="pt",
    )

loader = DataLoader(dataset, batch_size=16, collate_fn=collate_dynamic)
```

### Continuous Batching

Used by production LLM serving frameworks (vLLM, TGI). New requests join the
batch as slots free up — no waiting for the entire batch to finish. Maximizes
GPU utilization for autoregressive generation.

**Key property:** Different requests in the batch can be at different generation
steps. Requires PagedAttention (vLLM) or similar mechanism to manage KV cache
efficiently.

---

## 7. Model Serving: Decision Guide

| Framework        | Best For                          | Latency  | Throughput | Complexity |
|------------------|-----------------------------------|----------|------------|------------|
| FastAPI+uvicorn  | Simple models, prototypes, ≤10 QPS| Low-Med  | Low        | Low        |
| vLLM             | LLM serving, high throughput      | Low      | Very High  | Medium     |
| TGI              | HuggingFace models, streaming     | Low      | High       | Medium     |
| Triton           | Multi-model, multi-framework      | Lowest   | Highest    | High       |

### FastAPI + Uvicorn (Simple Serving)

```python
from fastapi import FastAPI
from pydantic import BaseModel
import torch
import uvicorn

app = FastAPI()

# Load model at startup
model = load_model()
model.eval()

class PredictionRequest(BaseModel):
    text: str
    max_length: int = 128

class PredictionResponse(BaseModel):
    output: str
    latency_ms: float

@app.post("/predict", response_model=PredictionResponse)
async def predict(request: PredictionRequest):
    import time
    start = time.perf_counter()

    inputs = tokenizer(request.text, return_tensors="pt").to("cuda")
    with torch.no_grad():
        outputs = model.generate(**inputs, max_new_tokens=request.max_length)
    result = tokenizer.decode(outputs[0], skip_special_tokens=True)

    latency = (time.perf_counter() - start) * 1000
    return PredictionResponse(output=result, latency_ms=latency)

@app.get("/health")
async def health():
    return {"status": "healthy", "gpu_available": torch.cuda.is_available()}

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000, workers=1)  # 1 worker for GPU
```

### vLLM (High-Throughput LLM Serving)

```python
from vllm import LLM, SamplingParams

# vLLM with PagedAttention — optimal for LLM serving
llm = LLM(
    model="meta-llama/Llama-3.1-8B",
    quantization="awq",              # or "gptq", "squeezellm"
    dtype="half",
    gpu_memory_utilization=0.85,     # leave 15% headroom on ⟦ gpu ⟧
    max_model_len=4096,
    enforce_eager=False,             # use CUDA graphs
)

sampling_params = SamplingParams(
    temperature=0.7,
    top_p=0.9,
    max_tokens=256,
)

# Batch inference with continuous batching
outputs = llm.generate(["Explain quantum computing:", "Write a poem:"], sampling_params)
for output in outputs:
    print(output.outputs[0].text)
```

```bash
# vLLM as OpenAI-compatible API server
python -m vllm.entrypoints.openai.api_server \
    --model meta-llama/Llama-3.1-8B \
    --quantization awq \
    --gpu-memory-utilization 0.85 \
    --max-model-len 4096 \
    --port 8000
```

### Triton Inference Server

```bash
# Model repository structure
model_repository/
├── my_model/
│   ├── config.pbtxt
│   ├── 1/
│   │   └── model.onnx        # or model.plan (TensorRT)
│   └── labels.txt

# Launch Triton with Docker
docker run --gpus=1 --rm -p 8000:8000 -p 8001:8001 -p 8002:8002 \
    -v $(pwd)/model_repository:/models \
    nvcr.io/nvidia/tritoninferenceserver:24.01-py3 \
    tritonserver --model-repository=/models
```

---

## 8. Latency SLA: Batch Size vs p99 Tradeoff

The fundamental tradeoff: larger batches increase throughput but increase p99
latency because the last request in a batch waits for the entire batch to process.

### Tuning Methodology

```python
import json

def find_optimal_batch_size(
    model,
    input_shape,
    target_p99_ms: float,
    max_batch_size: int = 64,
) -> dict:
    """Binary search for the largest batch size that meets p99 SLA."""

    results = []
    for batch_size in [1, 2, 4, 8, 16, 32, 64]:
        if batch_size > max_batch_size:
            break

        input_data = torch.randn(batch_size, *input_shape, device="cuda")
        stats = measure_latency(model, input_data, num_warmup=50, num_iterations=200)
        stats["batch_size"] = batch_size
        stats["meets_sla"] = stats["p99_ms"] <= target_p99_ms
        results.append(stats)

        print(f"batch={batch_size:3d} | p99={stats['p99_ms']:7.2f}ms | "
              f"throughput={stats['throughput_qps'] * batch_size:8.1f} items/sec | "
              f"SLA={'PASS' if stats['meets_sla'] else 'FAIL'}")

    # Find optimal: largest batch that passes SLA
    passing = [r for r in results if r["meets_sla"]]
    optimal = max(passing, key=lambda r: r["batch_size"]) if passing else None

    return {
        "optimal_batch_size": optimal["batch_size"] if optimal else 1,
        "optimal_throughput": optimal["throughput_qps"] * optimal["batch_size"] if optimal else 0,
        "all_results": results,
    }

# Example: find optimal batch for 50ms p99 SLA
result = find_optimal_batch_size(model, (3, 224, 224), target_p99_ms=50.0)
print(f"\nOptimal batch size: {result['optimal_batch_size']}")
print(f"Throughput: {result['optimal_throughput']:.1f} items/sec")
```

### SLA Guidelines for ⟦ gpu ⟧

| Use Case              | Target p99  | Recommended Strategy                    |
|-----------------------|-------------|-----------------------------------------|
| Real-time chat        | <100ms      | batch=1, CUDA graphs, INT4/INT8         |
| API endpoint          | <500ms      | dynamic batching, batch=4-8             |
| Batch processing      | <5s         | maximize batch size, throughput focus    |
| Offline analytics     | N/A         | max batch, max throughput               |

---

## 9. Anti-Patterns

### 9.1 Quantizing Without Evaluation

**Wrong:**
```python
# Quantize and ship — no quality check
model = AutoModelForCausalLM.from_pretrained(model_path, load_in_4bit=True)
# ... deploy directly
```

**Right:**
```python
# Always evaluate before and after quantization
baseline_metrics = evaluate(original_model, eval_dataset)
quantized_metrics = evaluate(quantized_model, eval_dataset)

degradation = {
    k: (baseline_metrics[k] - quantized_metrics[k]) / baseline_metrics[k] * 100
    for k in baseline_metrics
}

for metric, pct in degradation.items():
    print(f"{metric}: {pct:.2f}% degradation")
    if pct > 5.0:
        print(f"  WARNING: {metric} degradation exceeds 5% threshold")
```

### 9.2 Ignoring Calibration Data

GPTQ and INT8 TensorRT require calibration data representative of production inputs.
Using random data or mismatched domain data leads to poor quantization ranges and
silent accuracy loss.

**Rule:** Calibration data must come from the same distribution as production data.
Use 128-512 representative samples. Include edge cases.

### 9.3 Premature Optimization

**Wrong order:**
1. Quantize to INT4
2. Add TensorRT
3. Profile and discover the bottleneck is data loading

**Right order:**
1. Profile the baseline (FP32/FP16)
2. Identify the actual bottleneck (compute? memory? I/O? CPU?)
3. Apply the appropriate optimization
4. Profile again to confirm improvement
5. Repeat

### 9.4 Not Profiling Before Optimizing

Every optimization decision must be data-driven. Profile first, optimize second.

```python
# Step 1: Always start here
stats = measure_latency(model, input_data)
mem_stats = measure_peak_memory(model, input_data)

print(f"Baseline — p99: {stats['p99_ms']:.2f}ms, VRAM: {mem_stats['peak_gb']:.2f}GB")

# Step 2: Identify bottleneck
# - If VRAM > 7GB on ⟦ gpu ⟧ → quantize
# - If p99 > target → profile with torch.profiler to find hotspot
# - If GPU utilization < 80% → batching or data loading is the bottleneck
# - If GPU utilization > 95% and p99 still high → need smaller model or better hardware
```

### 9.5 Using FP16 Instead of BF16 on ⟦ gpu ⟧

On  (⟦ gpu ⟧), BF16 offers the same throughput as FP16 but with
better numerical stability due to its larger exponent range. Always prefer
`torch.bfloat16` over `torch.float16` on this hardware unless a library
explicitly requires FP16.

### 9.6 Ignoring KV Cache Memory for LLMs

For autoregressive LLM inference, the KV cache grows linearly with sequence
length and batch size. A model that fits in VRAM at batch_size=1 may OOM at
batch_size=4 due to KV cache growth.

**KV cache memory estimation:**
```
kv_cache_bytes = 2 * num_layers * 2 * hidden_dim * seq_len * batch_size * dtype_bytes
```

For a 7B model (32 layers, 4096 hidden, FP16) at seq_len=2048, batch_size=1:
```
2 * 32 * 2 * 4096 * 2048 * 1 * 2 bytes = ~2 GB
```

This is why PagedAttention (vLLM) is critical — it manages KV cache memory
efficiently by allocating non-contiguous memory blocks on demand.
