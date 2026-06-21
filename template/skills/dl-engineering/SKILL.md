---
name: dl-engineering
description: Deep Learning Engineering with PyTorch - training loops, GPU memory management, mixed precision, torch.compile, distributed training, checkpointing, and debugging. Use when building neural networks, optimizing training, or debugging GPU/CUDA issues.
paths:
  - "**/*neural*.py"
  - "**/*model*.py"
  - "**/*train*.py"
  - "**/*torch*.py"
  - "**/*lightning*.py"
  - "**/*.pt"
  - "**/*.pth"
effort: high
---

# Deep Learning Engineering - PyTorch 2025

## Principio Fundamental

```
"PyTorch maneja el forward. Lightning maneja el resto."
```

| Concepto | PyTorch Puro | PyTorch Lightning |
|----------|--------------|-------------------|
| Boilerplate | ~200 líneas | ~20 líneas |
| Multi-GPU | Manual | `Trainer(devices=4)` |
| Mixed Precision | Manual | `Trainer(precision="16-mixed")` |
| Checkpointing | Manual | Automático |
| Logging | Manual | Automático |

---

## Training Loop - PyTorch Puro

### Loop Básico (Referencia)
```python
import torch
import torch.nn as nn
from torch.utils.data import DataLoader

# Setup
model = MyModel().to("cuda")
optimizer = torch.optim.AdamW(model.parameters(), lr=1e-4)
criterion = nn.CrossEntropyLoss()

# Training loop
model.train()
for epoch in range(num_epochs):
    for batch_idx, (data, target) in enumerate(train_loader):
        data, target = data.to("cuda"), target.to("cuda")
        
        optimizer.zero_grad()           # 1. Clear gradients
        output = model(data)            # 2. Forward pass
        loss = criterion(output, target) # 3. Compute loss
        loss.backward()                  # 4. Backward pass
        optimizer.step()                 # 5. Update weights
        
        # Log (detach para evitar memory leak)
        if batch_idx % 100 == 0:
            print(f"Loss: {loss.item():.4f}")  # .item() detach scalar
```

### [WARN] Errores Comunes en Training Loop

```python
# [FAIL] MEMORY LEAK - loss acumulado mantiene grafo
total_loss = 0
for batch in loader:
    loss = model(batch)
    total_loss += loss  # ¡Acumula historial de gradientes!

# [PASS] CORRECTO - usar .item() o .detach()
total_loss = 0
for batch in loader:
    loss = model(batch)
    total_loss += loss.item()  # Scalar, sin grafo
    # o: total_loss += loss.detach()
```

---

## PyTorch Lightning - Estructura Recomendada

### LightningModule Completo
```python
import lightning as L
import torch
import torch.nn as nn
import torch.nn.functional as F
from torchmetrics import Accuracy

class LitClassifier(L.LightningModule):
    def __init__(self, num_classes: int = 10, lr: float = 1e-3):
        super().__init__()
        # Guarda hiperparámetros automáticamente
        self.save_hyperparameters()
        
        # Arquitectura
        self.model = nn.Sequential(
            nn.Linear(784, 256),
            nn.ReLU(),
            nn.Dropout(0.2),
            nn.Linear(256, num_classes)
        )
        
        # Métricas
        self.train_acc = Accuracy(task="multiclass", num_classes=num_classes)
        self.val_acc = Accuracy(task="multiclass", num_classes=num_classes)
    
    def forward(self, x):
        """Usado para inferencia."""
        return self.model(x)
    
    def training_step(self, batch, batch_idx):
        """Define UN paso de training."""
        x, y = batch
        logits = self(x)
        loss = F.cross_entropy(logits, y)
        
        # Log métricas (automático a TensorBoard/W&B)
        self.log("train_loss", loss, prog_bar=True)
        self.train_acc(logits, y)
        self.log("train_acc", self.train_acc, on_step=False, on_epoch=True)
        
        return loss  # Lightning hace .backward() automáticamente
    
    def validation_step(self, batch, batch_idx):
        x, y = batch
        logits = self(x)
        loss = F.cross_entropy(logits, y)
        
        self.log("val_loss", loss, prog_bar=True)
        self.val_acc(logits, y)
        self.log("val_acc", self.val_acc, on_step=False, on_epoch=True)
    
    def configure_optimizers(self):
        """Configura optimizer y scheduler."""
        optimizer = torch.optim.AdamW(
            self.parameters(), 
            lr=self.hparams.lr,
            weight_decay=0.01
        )
        scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(
            optimizer, T_max=100
        )
        return {
            "optimizer": optimizer,
            "lr_scheduler": {
                "scheduler": scheduler,
                "monitor": "val_loss",
            }
        }
```

### Trainer con Todas las Features
```python
from lightning.pytorch.callbacks import (
    ModelCheckpoint, 
    EarlyStopping,
    LearningRateMonitor
)
from lightning.pytorch.loggers import WandbLogger

# Callbacks
checkpoint_callback = ModelCheckpoint(
    dirpath="checkpoints/",
    filename="{epoch}-{val_loss:.2f}",
    save_top_k=3,
    monitor="val_loss",
    mode="min"
)

early_stop = EarlyStopping(
    monitor="val_loss",
    patience=10,
    mode="min"
)

lr_monitor = LearningRateMonitor(logging_interval="step")

# Logger
logger = WandbLogger(project="my-project", name="experiment-1")

# Trainer
trainer = L.Trainer(
    max_epochs=100,
    accelerator="gpu",
    devices=1,                          # o "auto" para usar todos
    precision="16-mixed",               # Mixed precision automático
    callbacks=[checkpoint_callback, early_stop, lr_monitor],
    logger=logger,
    gradient_clip_val=1.0,              # Gradient clipping
    accumulate_grad_batches=4,          # Gradient accumulation
    val_check_interval=0.25,            # Validar 4 veces por época
    log_every_n_steps=50,
    deterministic=True,                 # Reproducibilidad
)

# Train
trainer.fit(model, train_loader, val_loader)

# Test (solo al final, antes de publicar)
trainer.test(model, test_loader)
```

---

## Mixed Precision Training (AMP)

### ¿Por Qué Mixed Precision?
```
┌─────────────────────────────────────────────────────────────┐
│  FP16/BF16 vs FP32:                                        │
│  • 2x menos memoria                                        │
│  • 2-3x más rápido en Tensor Cores                         │
│  • Sin pérdida de accuracy (con GradScaler)                │
└─────────────────────────────────────────────────────────────┘
```

### BF16 vs FP16
| GPU | Recomendación |
|-----|---------------|
| Ampere+ (A100, RTX 30xx, H100) | **BF16** (más estable) |
| Turing, Volta (V100, RTX 20xx) | FP16 con GradScaler |
| Sin Tensor Cores | No usar AMP |

### PyTorch Puro - AMP Moderno (2025)
```python
import torch
from torch.amp import autocast, GradScaler

# Detectar mejor dtype
amp_dtype = torch.bfloat16 if torch.cuda.is_bf16_supported() else torch.float16

# GradScaler solo necesario para FP16 (no BF16)
scaler = GradScaler("cuda", enabled=(amp_dtype == torch.float16))

model = MyModel().cuda()
optimizer = torch.optim.AdamW(model.parameters(), lr=1e-4)

for epoch in range(num_epochs):
    for data, target in train_loader:
        data, target = data.cuda(), target.cuda()
        
        optimizer.zero_grad()
        
        # autocast solo en forward pass
        with autocast(device_type="cuda", dtype=amp_dtype):
            output = model(data)
            loss = criterion(output, target)
        
        # Backward FUERA de autocast
        scaler.scale(loss).backward()
        scaler.step(optimizer)
        scaler.update()
```

### Lightning - Una Línea
```python
trainer = L.Trainer(
    precision="16-mixed",  # FP16 con GradScaler
    # o
    precision="bf16-mixed",  # BF16 (Ampere+)
)
```

### Reglas para Evitar NaNs
```
1. Usar BF16 en Ampere+ (más tolerante a overflow)
2. GradScaler solo con FP16, no con BF16
3. Loss functions en FP32 (softmax, cross_entropy)
4. Normalización en FP32 (LayerNorm, BatchNorm)
5. Gradient clipping antes de optimizer.step()
```

---

## GPU Memory Management

### Diagnóstico de Memoria
```python
import torch

# Ver memoria usada
print(f"Allocated: {torch.cuda.memory_allocated() / 1e9:.2f} GB")
print(f"Reserved:  {torch.cuda.memory_reserved() / 1e9:.2f} GB")
print(f"Max Allocated: {torch.cuda.max_memory_allocated() / 1e9:.2f} GB")

# Resumen completo
print(torch.cuda.memory_summary())

# Reset estadísticas
torch.cuda.reset_peak_memory_stats()
```

### Soluciones a CUDA Out of Memory

| Técnica | Reducción Memoria | Complejidad |
|---------|-------------------|-------------|
| Reducir batch size | Variable | Trivial |
| Mixed Precision (AMP) | ~50% | Baja |
| Gradient Accumulation | Simula batch grande | Baja |
| Gradient Checkpointing | ~30-50% | Media |
| torch.cuda.empty_cache() | Variable | Trivial |
| Model Sharding (FSDP) | Escala a multi-GPU | Alta |

### Gradient Accumulation
```python
accumulation_steps = 4
effective_batch_size = batch_size * accumulation_steps

optimizer.zero_grad()
for i, (data, target) in enumerate(train_loader):
    with autocast(device_type="cuda"):
        output = model(data)
        loss = criterion(output, target)
        loss = loss / accumulation_steps  # Normalizar loss
    
    scaler.scale(loss).backward()
    
    if (i + 1) % accumulation_steps == 0:
        scaler.step(optimizer)
        scaler.update()
        optimizer.zero_grad()
```

### Gradient Checkpointing
```python
from torch.utils.checkpoint import checkpoint

class TransformerBlock(nn.Module):
    def forward(self, x):
        # Recomputar activaciones en backward (ahorra memoria)
        return checkpoint(self._forward, x, use_reentrant=False)
    
    def _forward(self, x):
        # Forward real
        x = self.attention(x)
        x = self.feedforward(x)
        return x
```

### Liberar Memoria Correctamente
```python
# Después de inferencia/evaluación
del output, loss
torch.cuda.empty_cache()  # Liberar cache no usado

# En evaluación - no guardar gradientes
with torch.no_grad():
    output = model(data)
```

---

## torch.compile - Aceleración 2x

### Uso Básico
```python
import torch

model = MyModel().cuda()

# Compilar modelo - 1 línea
model = torch.compile(model)

# Primera llamada: compila (lento)
# Llamadas siguientes: rápido
output = model(input)
```

### Modos de Compilación
```python
# default - balance velocidad/compilación
model = torch.compile(model)

# reduce-overhead - mejor para batches pequeños, usa CUDA Graphs
model = torch.compile(model, mode="reduce-overhead")

# max-autotune - máxima velocidad, compilación lenta
model = torch.compile(model, mode="max-autotune")

# fullgraph - error si hay graph breaks (debugging)
model = torch.compile(model, fullgraph=True)
```

### Cuándo Usar Cada Modo
| Modo | Caso de Uso |
|------|-------------|
| `default` | General, primer intento |
| `reduce-overhead` | Batches pequeños, muchas ops pequeñas |
| `max-autotune` | Producción, shapes fijos |
| `fullgraph=True` | Debugging graph breaks |

### Evitar Graph Breaks
```python
# [FAIL] Graph break - control flow con tensor
if x.sum() > 0:  # Depende de valor de tensor
    ...

# [FAIL] Graph break - print/logging
print(f"Loss: {loss}")

# [FAIL] Graph break - operaciones in-place problemáticas
x[0] = 1

# [PASS] Logging fuera de la función compilada
@torch.compile
def forward(x):
    return model(x)

output = forward(x)
print(f"Output: {output}")  # Fuera de compile
```

### Debugging torch.compile
```bash
# Ver recompilaciones
TORCH_LOGS=recompiles python train.py

# Ver graph breaks
TORCH_LOGS=graph_breaks python train.py

# Ver código generado
TORCH_LOGS=output_code python train.py
```

---

## DataLoader Optimizado

### Configuración Óptima
```python
from torch.utils.data import DataLoader

train_loader = DataLoader(
    dataset,
    batch_size=64,
    shuffle=True,
    num_workers=4,              # Regla: 4 * num_GPUs
    pin_memory=True,            # Transferencia GPU más rápida
    persistent_workers=True,    # No recrear workers cada época
    prefetch_factor=2,          # Batches a pre-cargar por worker
    drop_last=True,             # Evitar batch incompleto final
)
```

### Reglas de num_workers
```
num_workers = 0  → Debugging (single process)
num_workers = 4  → Default para 1 GPU
num_workers = 4 * num_gpus  → Multi-GPU
num_workers > 8  → Puede causar overhead
```

### pin_memory Explicado
```python
# pin_memory=True: datos en "pinned memory" (page-locked)
# Transferencia CPU→GPU más rápida (async)
# Costo: más RAM del sistema

# Usar cuando:
# - GPU es el bottleneck (común)
# - Tienes suficiente RAM

# NO usar cuando:
# - RAM es limitada
# - CPU es el bottleneck
```

---

## Checkpointing y Resuming

### Guardar Checkpoint Completo
```python
# Guardar
checkpoint = {
    'epoch': epoch,
    'model_state_dict': model.state_dict(),
    'optimizer_state_dict': optimizer.state_dict(),
    'scheduler_state_dict': scheduler.state_dict(),
    'scaler_state_dict': scaler.state_dict(),  # Si usas AMP
    'loss': loss,
    'config': config,
}
torch.save(checkpoint, f'checkpoint_epoch_{epoch}.pt')

# Cargar
checkpoint = torch.load('checkpoint_epoch_10.pt', weights_only=False)
model.load_state_dict(checkpoint['model_state_dict'])
optimizer.load_state_dict(checkpoint['optimizer_state_dict'])
scheduler.load_state_dict(checkpoint['scheduler_state_dict'])
scaler.load_state_dict(checkpoint['scaler_state_dict'])
start_epoch = checkpoint['epoch'] + 1
```

### Lightning - Automático
```python
# Lightning guarda automáticamente con ModelCheckpoint callback

# Resumir desde checkpoint
trainer.fit(model, train_loader, ckpt_path="checkpoints/last.ckpt")
```

---

## Reproducibilidad

### Setup Completo
```python
import random
import numpy as np
import torch
import os

def set_seed(seed: int = 42):
    """Reproducibilidad completa."""
    random.seed(seed)
    np.random.seed(seed)
    torch.manual_seed(seed)
    
    if torch.cuda.is_available():
        torch.cuda.manual_seed(seed)
        torch.cuda.manual_seed_all(seed)
    
    # Operaciones determinísticas (más lento)
    torch.backends.cudnn.deterministic = True
    torch.backends.cudnn.benchmark = False
    
    os.environ["PYTHONHASHSEED"] = str(seed)

# Llamar al inicio
set_seed(42)
```

### Lightning
```python
from lightning.pytorch import seed_everything

seed_everything(42, workers=True)

trainer = L.Trainer(deterministic=True)
```

### [WARN] Nota sobre cudnn.benchmark
```python
# cudnn.benchmark = True  → Más rápido, no determinístico
# cudnn.benchmark = False → Determinístico, más lento

# Para training normal (no reproducibilidad estricta):
torch.backends.cudnn.benchmark = True  # Auto-tune kernels
```

---

## Distributed Training

### DataParallel (Simple, No Recomendado)
```python
# Simple pero ineficiente (GIL bottleneck)
model = nn.DataParallel(model)
```

### DistributedDataParallel (Recomendado)
```python
import torch.distributed as dist
from torch.nn.parallel import DistributedDataParallel as DDP

# Inicializar proceso
dist.init_process_group(backend="nccl")
local_rank = int(os.environ["LOCAL_RANK"])
torch.cuda.set_device(local_rank)

# Modelo DDP
model = MyModel().to(local_rank)
model = DDP(model, device_ids=[local_rank])

# Sampler distribuido
from torch.utils.data.distributed import DistributedSampler
sampler = DistributedSampler(dataset, shuffle=True)
loader = DataLoader(dataset, batch_size=64, sampler=sampler)

# En cada época
for epoch in range(num_epochs):
    sampler.set_epoch(epoch)  # Importante para shuffle correcto
    for batch in loader:
        ...
```

### Lightning - Una Línea
```python
trainer = L.Trainer(
    accelerator="gpu",
    devices=4,              # 4 GPUs
    strategy="ddp",         # DistributedDataParallel
    # o
    strategy="fsdp",        # FullyShardedDataParallel (modelos grandes)
)
```

### Lanzar Training Distribuido
```bash
# torchrun (recomendado)
torchrun --nproc_per_node=4 train.py

# Lightning CLI
python train.py --trainer.devices=4 --trainer.strategy=ddp
```

---

## Debugging DL Models

### Debugging Básico
```python
# 1. Verificar shapes
print(f"Input: {x.shape}, Output: {output.shape}")

# 2. Verificar gradientes
for name, param in model.named_parameters():
    if param.grad is not None:
        print(f"{name}: grad mean={param.grad.mean():.6f}")

# 3. Detectar NaN/Inf
torch.autograd.set_detect_anomaly(True)  # Slow pero útil

# 4. Overfit un batch (sanity check)
single_batch = next(iter(train_loader))
for _ in range(1000):
    loss = train_step(single_batch)
    print(f"Loss: {loss:.4f}")  # Debe → 0
```

### Lightning Debugging
```python
trainer = L.Trainer(
    fast_dev_run=True,      # 1 batch train + val (sanity check)
    overfit_batches=1,      # Overfit 1 batch (debug)
    limit_train_batches=10, # Solo 10 batches
    detect_anomaly=True,    # Detectar NaN/Inf
    profiler="simple",      # Profile básico
)
```

### Profiling
```python
from torch.profiler import profile, ProfilerActivity, tensorboard_trace_handler

with profile(
    activities=[ProfilerActivity.CPU, ProfilerActivity.CUDA],
    schedule=torch.profiler.schedule(wait=1, warmup=1, active=3),
    on_trace_ready=tensorboard_trace_handler("./log"),
    record_shapes=True,
    with_stack=True
) as prof:
    for step, batch in enumerate(train_loader):
        train_step(batch)
        prof.step()
        if step >= 5:
            break

# Ver resultados
# tensorboard --logdir=./log
```

---

## Optimizers y Schedulers 2025

### Optimizers Recomendados
```python
# AdamW - Default para la mayoría
optimizer = torch.optim.AdamW(
    model.parameters(),
    lr=1e-4,
    weight_decay=0.01,
    betas=(0.9, 0.999)
)

# Para ViTs y Transformers grandes
# 8-bit Adam (ahorra memoria)
# pip install bitsandbytes
import bitsandbytes as bnb
optimizer = bnb.optim.AdamW8bit(model.parameters(), lr=1e-4)
```

### Learning Rate Schedulers
```python
# Cosine Annealing (muy usado)
scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(
    optimizer, T_max=num_epochs
)

# Cosine con warmup (Transformers)
from torch.optim.lr_scheduler import OneCycleLR
scheduler = OneCycleLR(
    optimizer,
    max_lr=1e-3,
    total_steps=num_epochs * len(train_loader),
    pct_start=0.1  # 10% warmup
)

# Reduce on Plateau
scheduler = torch.optim.lr_scheduler.ReduceLROnPlateau(
    optimizer, mode='min', factor=0.1, patience=10
)
```

---

## Estructura de Proyecto DL

```
my_dl_project/
├── configs/
│   ├── model.yaml
│   └── train.yaml
├── data/
│   └── dataset.py
├── models/
│   ├── __init__.py
│   ├── base.py
│   └── transformer.py
├── trainers/
│   └── lightning_module.py
├── scripts/
│   ├── train.py
│   └── evaluate.py
├── notebooks/
│   └── exploration.ipynb
├── checkpoints/           # .gitignore
├── logs/                  # .gitignore
├── pyproject.toml
└── README.md
```

---

## Checklist DL Engineering

### Pre-Training
```
□ Seed configurado para reproducibilidad
□ DataLoader optimizado (num_workers, pin_memory)
□ Mixed precision configurado (BF16/FP16)
□ Gradient clipping habilitado
□ Checkpointing configurado
□ Logging configurado (W&B/TensorBoard)
□ torch.compile evaluado
□ Sanity check: overfit un batch
```

### Durante Training
```
□ Monitorear GPU utilization (nvidia-smi)
□ Monitorear memoria GPU
□ Verificar que loss decrece
□ Verificar learning rate schedule
□ Checkpoints guardándose
□ No hay NaN/Inf
```

### Anti-Patterns
```
[FAIL] loss += batch_loss (memory leak - usar .item())
[FAIL] Olvidar optimizer.zero_grad()
[FAIL] Olvidar model.train() / model.eval()
[FAIL] Crear tensores en loop sin .detach()
[FAIL] No usar with torch.no_grad() en inferencia
[FAIL] num_workers demasiado alto
[FAIL] Ignorar warnings de torch.compile
[FAIL] No verificar que gradientes fluyen
```
