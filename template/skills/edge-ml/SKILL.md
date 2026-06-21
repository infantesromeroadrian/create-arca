---
name: edge-ml
description: Complete guide for edge ML deployment including model optimization (quantization, pruning, distillation), TensorFlow Lite, ONNX Runtime Mobile, Core ML, and embedded inference. Use when deploying models to mobile devices, IoT, or resource-constrained environments.
---

# Edge ML & On-Device Inference

## Stack 2025

| Component | Tools |
|-----------|-------|
| Optimization | ONNX, TensorRT, OpenVINO |
| Mobile | TensorFlow Lite, Core ML, ONNX Runtime Mobile |
| Embedded | TFLite Micro, Edge Impulse, TinyML |
| Quantization | PyTorch, ONNX Runtime, TensorRT |
| Profiling | Netron, onnx-simplifier, benchmark tools |

---

## Optimization Techniques

### Technique Comparison

| Technique | Size Reduction | Speed Gain | Accuracy Loss |
|-----------|----------------|------------|---------------|
| FP16 Quantization | 2x | 1.5-2x | <1% |
| INT8 Quantization | 4x | 2-4x | 1-3% |
| Pruning (50%) | 2x | 1.5x | 1-2% |
| Knowledge Distillation | Variable | Variable | 1-5% |
| Architecture Search | Variable | Variable | Optimized |

---

## Quantization

### PyTorch Dynamic Quantization

```python
import torch

# Dynamic quantization (weights only, activations at runtime)
model_quantized = torch.quantization.quantize_dynamic(
    model,
    {torch.nn.Linear, torch.nn.LSTM},  # Layers to quantize
    dtype=torch.qint8,
)

# Compare sizes
def get_model_size(model):
    torch.save(model.state_dict(), "temp.pt")
    size = os.path.getsize("temp.pt") / 1e6
    os.remove("temp.pt")
    return size

print(f"Original: {get_model_size(model):.2f} MB")
print(f"Quantized: {get_model_size(model_quantized):.2f} MB")
```

### PyTorch Static Quantization

```python
import torch
from torch.quantization import get_default_qconfig, prepare, convert

# Prepare model
model.eval()
model.qconfig = get_default_qconfig("x86")  # or "qnnpack" for ARM

# Fuse modules (Conv+BN+ReLU)
model_fused = torch.quantization.fuse_modules(
    model,
    [["conv1", "bn1", "relu1"], ["conv2", "bn2", "relu2"]],
)

# Insert observers
model_prepared = prepare(model_fused)

# Calibration (run representative data)
with torch.no_grad():
    for batch in calibration_loader:
        model_prepared(batch)

# Convert to quantized
model_quantized = convert(model_prepared)
```

### ONNX Quantization

```python
from onnxruntime.quantization import quantize_dynamic, quantize_static, QuantType
from onnxruntime.quantization import CalibrationDataReader

# Dynamic quantization (no calibration needed)
quantize_dynamic(
    model_input="model.onnx",
    model_output="model_int8.onnx",
    weight_type=QuantType.QInt8,
)

# Static quantization (requires calibration)
class CalibrationReader(CalibrationDataReader):
    def __init__(self, calibration_data):
        self.data = iter(calibration_data)
    
    def get_next(self):
        try:
            return {"input": next(self.data)}
        except StopIteration:
            return None

quantize_static(
    model_input="model.onnx",
    model_output="model_int8_static.onnx",
    calibration_data_reader=CalibrationReader(calibration_data),
    quant_format=QuantFormat.QDQ,  # Quantize-Dequantize format
    per_channel=True,
    weight_type=QuantType.QInt8,
    activation_type=QuantType.QUInt8,
)
```

### TensorRT Quantization

```python
import tensorrt as trt

def build_engine_int8(onnx_path, calibration_data):
    logger = trt.Logger(trt.Logger.WARNING)
    builder = trt.Builder(logger)
    network = builder.create_network(
        1 << int(trt.NetworkDefinitionCreationFlag.EXPLICIT_BATCH)
    )
    parser = trt.OnnxParser(network, logger)
    
    # Parse ONNX
    with open(onnx_path, "rb") as f:
        parser.parse(f.read())
    
    # Configure INT8
    config = builder.create_builder_config()
    config.set_flag(trt.BuilderFlag.INT8)
    
    # Calibrator
    config.int8_calibrator = EntropyCalibrator(calibration_data)
    
    # Build engine
    engine = builder.build_serialized_network(network, config)
    return engine
```

---

## Pruning

### Magnitude Pruning (PyTorch)

```python
import torch.nn.utils.prune as prune

# Prune individual layer
prune.l1_unstructured(model.fc1, name="weight", amount=0.3)  # 30% sparsity

# Global pruning (prune smallest weights across model)
parameters_to_prune = [
    (model.conv1, "weight"),
    (model.conv2, "weight"),
    (model.fc1, "weight"),
]

prune.global_unstructured(
    parameters_to_prune,
    pruning_method=prune.L1Unstructured,
    amount=0.5,  # 50% global sparsity
)

# Check sparsity
def get_sparsity(model):
    zeros = sum((p == 0).sum().item() for p in model.parameters())
    total = sum(p.numel() for p in model.parameters())
    return zeros / total * 100

print(f"Sparsity: {get_sparsity(model):.1f}%")

# Make pruning permanent
for module, name in parameters_to_prune:
    prune.remove(module, name)
```

### Structured Pruning (Filter Pruning)

```python
import torch.nn.utils.prune as prune

# Remove entire filters (structured)
prune.ln_structured(
    model.conv1,
    name="weight",
    amount=0.3,
    n=2,  # L2 norm
    dim=0,  # Prune output channels
)

# This actually reduces model size (unlike unstructured)
```

### Iterative Pruning with Fine-tuning

```python
def iterative_pruning(model, train_loader, val_loader, target_sparsity=0.9, steps=10):
    """Gradually prune and fine-tune."""
    sparsity_per_step = 1 - (1 - target_sparsity) ** (1 / steps)
    
    for step in range(steps):
        # Prune
        for name, module in model.named_modules():
            if isinstance(module, (torch.nn.Conv2d, torch.nn.Linear)):
                prune.l1_unstructured(module, name="weight", amount=sparsity_per_step)
        
        # Fine-tune
        optimizer = torch.optim.Adam(model.parameters(), lr=1e-4)
        for epoch in range(5):
            train_epoch(model, train_loader, optimizer)
        
        # Evaluate
        accuracy = evaluate(model, val_loader)
        sparsity = get_sparsity(model)
        print(f"Step {step+1}: Sparsity={sparsity:.1f}%, Accuracy={accuracy:.2f}%")
    
    # Make permanent
    for name, module in model.named_modules():
        if isinstance(module, (torch.nn.Conv2d, torch.nn.Linear)):
            prune.remove(module, "weight")
    
    return model
```

---

## Knowledge Distillation

### Basic Distillation

```python
import torch
import torch.nn as nn
import torch.nn.functional as F

class DistillationLoss(nn.Module):
    def __init__(self, temperature=4.0, alpha=0.5):
        super().__init__()
        self.temperature = temperature
        self.alpha = alpha
        self.ce_loss = nn.CrossEntropyLoss()
    
    def forward(self, student_logits, teacher_logits, labels):
        # Soft targets from teacher
        soft_targets = F.softmax(teacher_logits / self.temperature, dim=1)
        soft_student = F.log_softmax(student_logits / self.temperature, dim=1)
        
        # KL divergence (soft loss)
        distill_loss = F.kl_div(soft_student, soft_targets, reduction="batchmean")
        distill_loss *= self.temperature ** 2
        
        # Hard loss (standard CE)
        hard_loss = self.ce_loss(student_logits, labels)
        
        # Combined loss
        return self.alpha * distill_loss + (1 - self.alpha) * hard_loss

# Training loop
teacher.eval()
student.train()

criterion = DistillationLoss(temperature=4.0, alpha=0.7)
optimizer = torch.optim.Adam(student.parameters(), lr=1e-3)

for batch in train_loader:
    inputs, labels = batch
    
    with torch.no_grad():
        teacher_logits = teacher(inputs)
    
    student_logits = student(inputs)
    
    loss = criterion(student_logits, teacher_logits, labels)
    
    optimizer.zero_grad()
    loss.backward()
    optimizer.step()
```

### Feature Distillation

```python
class FeatureDistillationLoss(nn.Module):
    """Distill intermediate features, not just logits."""
    
    def __init__(self, student_channels, teacher_channels):
        super().__init__()
        # Projection to match dimensions
        self.projector = nn.Conv2d(student_channels, teacher_channels, 1)
    
    def forward(self, student_features, teacher_features):
        # Project student features
        projected = self.projector(student_features)
        
        # MSE loss on features
        return F.mse_loss(projected, teacher_features)

# Hook to extract intermediate features
student_features = []
teacher_features = []

def get_features(features_list):
    def hook(module, input, output):
        features_list.append(output)
    return hook

student.layer3.register_forward_hook(get_features(student_features))
teacher.layer3.register_forward_hook(get_features(teacher_features))
```

---

## TensorFlow Lite

### Conversion

```python
import tensorflow as tf

# Load model
model = tf.keras.models.load_model("model.h5")

# Basic conversion
converter = tf.lite.TFLiteConverter.from_keras_model(model)
tflite_model = converter.convert()

# Save
with open("model.tflite", "wb") as f:
    f.write(tflite_model)

# With quantization
converter = tf.lite.TFLiteConverter.from_keras_model(model)
converter.optimizations = [tf.lite.Optimize.DEFAULT]

# INT8 quantization (requires representative dataset)
def representative_dataset():
    for data in calibration_data:
        yield [data.astype(np.float32)]

converter.representative_dataset = representative_dataset
converter.target_spec.supported_ops = [tf.lite.OpsSet.TFLITE_BUILTINS_INT8]
converter.inference_input_type = tf.uint8
converter.inference_output_type = tf.uint8

tflite_quantized = converter.convert()
```

### Inference

```python
import numpy as np
import tensorflow as tf

# Load model
interpreter = tf.lite.Interpreter(model_path="model.tflite")
interpreter.allocate_tensors()

# Get input/output details
input_details = interpreter.get_input_details()
output_details = interpreter.get_output_details()

# Inference
def predict(input_data):
    interpreter.set_tensor(input_details[0]["index"], input_data)
    interpreter.invoke()
    return interpreter.get_tensor(output_details[0]["index"])

# Benchmark
import time

times = []
for _ in range(100):
    start = time.time()
    predict(test_input)
    times.append(time.time() - start)

print(f"Average inference: {np.mean(times)*1000:.2f} ms")
```

---

## ONNX Runtime Mobile

### Optimization for Mobile

```python
import onnx
from onnxruntime.transformers import optimizer

# Optimize ONNX model
optimized_model = optimizer.optimize_model(
    "model.onnx",
    model_type="bert",
    num_heads=12,
    hidden_size=768,
)
optimized_model.save_model_to_file("model_optimized.onnx")

# Convert to ORT format (smaller, faster loading)
import onnxruntime as ort

sess_options = ort.SessionOptions()
sess_options.optimized_model_filepath = "model.ort"
sess_options.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL

session = ort.InferenceSession("model.onnx", sess_options)
```

### Mobile Inference

```python
# Python (for testing, actual mobile uses native SDK)
import onnxruntime as ort

# Mobile-optimized session
sess_options = ort.SessionOptions()
sess_options.intra_op_num_threads = 4
sess_options.inter_op_num_threads = 1
sess_options.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL

# Use XNNPACK for ARM
providers = ["XNNPACKExecutionProvider", "CPUExecutionProvider"]

session = ort.InferenceSession(
    "model.onnx",
    sess_options,
    providers=providers,
)

# Inference
output = session.run(None, {"input": input_data})
```

---

## Core ML (Apple)

### Conversion with coremltools

```python
import coremltools as ct
import torch

# PyTorch to Core ML
model.eval()
traced = torch.jit.trace(model, example_input)

mlmodel = ct.convert(
    traced,
    inputs=[ct.TensorType(shape=example_input.shape)],
    minimum_deployment_target=ct.target.iOS15,
)

# Add metadata
mlmodel.author = "ML Team"
mlmodel.short_description = "Image classifier"
mlmodel.version = "1.0"

# Quantize
mlmodel_quantized = ct.models.neural_network.quantization_utils.quantize_weights(
    mlmodel,
    nbits=8,
)

mlmodel_quantized.save("model.mlpackage")
```

### With Neural Engine Optimization

```python
import coremltools as ct

mlmodel = ct.convert(
    traced,
    inputs=[ct.TensorType(shape=example_input.shape)],
    compute_units=ct.ComputeUnit.ALL,  # Use Neural Engine
    minimum_deployment_target=ct.target.iOS16,
)

# FP16 precision (faster on Neural Engine)
mlmodel_fp16 = ct.models.neural_network.quantization_utils.quantize_weights(
    mlmodel,
    nbits=16,
)
```

---

## Embedded / TinyML

### TensorFlow Lite Micro

```cpp
// C++ example for microcontrollers
#include "tensorflow/lite/micro/micro_interpreter.h"
#include "tensorflow/lite/micro/micro_mutable_op_resolver.h"

// Model data (converted to C array)
extern const unsigned char model_data[];
extern const int model_data_len;

// Tensor arena (memory for inference)
constexpr int kTensorArenaSize = 10 * 1024;
uint8_t tensor_arena[kTensorArenaSize];

void setup() {
    // Load model
    const tflite::Model* model = tflite::GetModel(model_data);
    
    // Create op resolver
    tflite::MicroMutableOpResolver<5> resolver;
    resolver.AddFullyConnected();
    resolver.AddSoftmax();
    
    // Create interpreter
    tflite::MicroInterpreter interpreter(
        model, resolver, tensor_arena, kTensorArenaSize
    );
    
    interpreter.AllocateTensors();
    
    // Get input tensor
    TfLiteTensor* input = interpreter.input(0);
    
    // Fill input data
    // input->data.f[0] = ...
    
    // Run inference
    interpreter.Invoke();
    
    // Get output
    TfLiteTensor* output = interpreter.output(0);
}
```

### Edge Impulse (No-Code TinyML)

```python
# Export model for Edge Impulse
# 1. Train in Edge Impulse Studio
# 2. Or upload custom model:

import requests

# Upload ONNX model
with open("model.onnx", "rb") as f:
    response = requests.post(
        "https://studio.edgeimpulse.com/v1/api/...",
        headers={"x-api-key": API_KEY},
        files={"file": f},
    )

# Deploy to device via Edge Impulse CLI
# $ edge-impulse-cli upload model.onnx
# $ edge-impulse-cli deploy --target arduino
```

---

## Benchmarking

### Model Profiling

```python
import onnxruntime as ort
import numpy as np
import time

def benchmark_model(model_path, input_shape, num_runs=100, warmup=10):
    """Benchmark ONNX model."""
    session = ort.InferenceSession(model_path)
    input_name = session.get_inputs()[0].name
    
    # Random input
    input_data = np.random.randn(*input_shape).astype(np.float32)
    
    # Warmup
    for _ in range(warmup):
        session.run(None, {input_name: input_data})
    
    # Benchmark
    times = []
    for _ in range(num_runs):
        start = time.perf_counter()
        session.run(None, {input_name: input_data})
        times.append(time.perf_counter() - start)
    
    return {
        "mean_ms": np.mean(times) * 1000,
        "std_ms": np.std(times) * 1000,
        "p95_ms": np.percentile(times, 95) * 1000,
        "p99_ms": np.percentile(times, 99) * 1000,
    }

# Compare models
original = benchmark_model("model.onnx", (1, 3, 224, 224))
quantized = benchmark_model("model_int8.onnx", (1, 3, 224, 224))

print(f"Original: {original['mean_ms']:.2f} ms")
print(f"Quantized: {quantized['mean_ms']:.2f} ms")
print(f"Speedup: {original['mean_ms'] / quantized['mean_ms']:.2f}x")
```

### Memory Profiling

```python
import tracemalloc
import torch

def measure_memory(model, input_tensor):
    """Measure peak memory usage."""
    tracemalloc.start()
    
    with torch.no_grad():
        output = model(input_tensor)
    
    current, peak = tracemalloc.get_traced_memory()
    tracemalloc.stop()
    
    return {
        "current_mb": current / 1e6,
        "peak_mb": peak / 1e6,
    }
```

---

## Deployment Checklist

```markdown
## Edge Deployment Checklist

### Model Optimization
- [ ] Profile baseline model (size, latency, memory)
- [ ] Apply quantization (INT8 or FP16)
- [ ] Consider pruning if needed
- [ ] Verify accuracy after optimization

### Target Platform
- [ ] Choose runtime (TFLite, ONNX Runtime, Core ML)
- [ ] Test on actual device hardware
- [ ] Benchmark with realistic inputs
- [ ] Test battery/thermal impact

### Integration
- [ ] Handle model loading efficiently
- [ ] Implement input preprocessing on-device
- [ ] Handle output postprocessing
- [ ] Add error handling for edge cases

### Maintenance
- [ ] Plan for model updates
- [ ] Implement A/B testing capability
- [ ] Add telemetry for monitoring
- [ ] Document optimization decisions
```

---

## Anti-patterns

| [FAIL] Don't | [PASS] Do |
|----------|-------|
| Quantize without calibration data | Use representative data |
| Skip accuracy validation | Test on held-out data |
| Assume INT8 always works | Profile actual speedup |
| Ignore model loading time | Optimize for cold start |
| Deploy without device testing | Test on target hardware |
| Over-optimize prematurely | Profile first, optimize bottlenecks |
