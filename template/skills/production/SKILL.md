---
name: production
description: ML model deployment and production best practices including FastAPI, Docker, Kubernetes, ONNX optimization, scaling, monitoring, and CI/CD. Use when deploying models to production, containerizing ML services, optimizing inference, or building production-grade APIs.
paths:
  - "**/Dockerfile*"
  - "**/docker-compose*"
  - "**/api*.py"
  - "**/serve*.py"
  - "**/deploy*"
  - "**/*.onnx"
  - "**/k8s/**"
  - "**/kubernetes/**"
---

# ML Production Deployment 2025

## Principio Fundamental

```
"A model in a notebook helps no one. A model in production helps everyone."
```

---

## Production Stack 2025

```
┌──────────────────────────────────────────────────────────────┐
│              ML Production Stack 2025                        │
├──────────────────────────────────────────────────────────────┤
│ API Framework     │ FastAPI 0.115+                          │
│ ASGI Server       │ Uvicorn + Gunicorn                      │
│ Containerization  │ Docker 25.0+                            │
│ Orchestration     │ Kubernetes 1.28+, Docker Compose        │
│ Model Optimization│ ONNX Runtime, TensorRT, torch.compile   │
│ Reverse Proxy     │ Nginx, Traefik                          │
│ Monitoring        │ Prometheus + Grafana                    │
│ Logging           │ Structured logging, ELK Stack           │
└──────────────────────────────────────────────────────────────┘
```

---

## FastAPI para ML Inference

### Servicio Básico
```python
# app/main.py
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field
from contextlib import asynccontextmanager
import numpy as np
import joblib

# Modelos Pydantic para validación
class PredictionRequest(BaseModel):
    features: list[float] = Field(..., min_length=4, max_length=4)
    
    model_config = {
        "json_schema_extra": {
            "examples": [{"features": [5.1, 3.5, 1.4, 0.2]}]
        }
    }

class PredictionResponse(BaseModel):
    prediction: int
    probability: float
    class_name: str

# Lifespan para cargar modelo una vez
@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup: cargar modelo
    app.state.model = joblib.load("models/model.pkl")
    app.state.class_names = ["setosa", "versicolor", "virginica"]
    yield
    # Shutdown: cleanup
    del app.state.model

app = FastAPI(
    title="ML Inference API",
    version="1.0.0",
    lifespan=lifespan,
)

@app.get("/health")
async def health_check():
    """Health check para load balancers."""
    return {"status": "healthy"}

@app.get("/ready")
async def readiness_check():
    """Readiness check - modelo cargado."""
    if not hasattr(app.state, "model"):
        raise HTTPException(status_code=503, detail="Model not loaded")
    return {"status": "ready"}

@app.post("/predict", response_model=PredictionResponse)
async def predict(request: PredictionRequest):
    """Endpoint de predicción."""
    features = np.array(request.features).reshape(1, -1)
    
    prediction = app.state.model.predict(features)[0]
    probability = app.state.model.predict_proba(features).max()
    
    return PredictionResponse(
        prediction=int(prediction),
        probability=float(probability),
        class_name=app.state.class_names[prediction],
    )
```

### Async con Batching
```python
import asyncio
from collections import deque
from typing import Any

class BatchProcessor:
    """Procesa requests en batches para mejor throughput GPU."""
    
    def __init__(self, model, max_batch_size: int = 32, max_wait_ms: int = 10):
        self.model = model
        self.max_batch_size = max_batch_size
        self.max_wait_ms = max_wait_ms
        self.queue: deque = deque()
        self.lock = asyncio.Lock()
    
    async def predict(self, features: np.ndarray) -> np.ndarray:
        """Add request to batch and wait for result."""
        future = asyncio.Future()
        
        async with self.lock:
            self.queue.append((features, future))
            
            if len(self.queue) >= self.max_batch_size:
                await self._process_batch()
        
        # Wait for result or timeout
        try:
            return await asyncio.wait_for(future, timeout=1.0)
        except asyncio.TimeoutError:
            raise HTTPException(status_code=504, detail="Prediction timeout")
    
    async def _process_batch(self):
        """Process all pending requests as a batch."""
        if not self.queue:
            return
        
        batch_items = []
        while self.queue and len(batch_items) < self.max_batch_size:
            batch_items.append(self.queue.popleft())
        
        # Stack features into batch
        features_batch = np.vstack([item[0] for item in batch_items])
        
        # Run inference
        predictions = self.model.predict(features_batch)
        
        # Return results
        for i, (_, future) in enumerate(batch_items):
            future.set_result(predictions[i])
```

### Structured Logging
```python
import logging
import json
from datetime import datetime
import time
from fastapi import Request

# JSON structured logger
class JSONFormatter(logging.Formatter):
    def format(self, record):
        log_obj = {
            "timestamp": datetime.utcnow().isoformat(),
            "level": record.levelname,
            "message": record.getMessage(),
            "module": record.module,
        }
        if hasattr(record, "extra"):
            log_obj.update(record.extra)
        return json.dumps(log_obj)

logger = logging.getLogger("ml_api")
handler = logging.StreamHandler()
handler.setFormatter(JSONFormatter())
logger.addHandler(handler)
logger.setLevel(logging.INFO)

# Middleware para logging de requests
@app.middleware("http")
async def log_requests(request: Request, call_next):
    start_time = time.perf_counter()
    
    response = await call_next(request)
    
    process_time = (time.perf_counter() - start_time) * 1000
    
    logger.info(
        "request_completed",
        extra={
            "method": request.method,
            "path": request.url.path,
            "status_code": response.status_code,
            "latency_ms": round(process_time, 2),
        }
    )
    
    # Add latency header
    response.headers["X-Process-Time-Ms"] = str(round(process_time, 2))
    return response
```

---

## Gunicorn + Uvicorn (Producción)

### Configuración Gunicorn
```python
# gunicorn_config.py
import multiprocessing

# Workers
workers = (2 * multiprocessing.cpu_count()) + 1
worker_class = "uvicorn.workers.UvicornWorker"

# Binding
bind = "0.0.0.0:8000"

# Timeouts
timeout = 120
graceful_timeout = 30
keepalive = 5

# Logging
accesslog = "-"
errorlog = "-"
loglevel = "info"

# Performance
worker_connections = 1000
max_requests = 10000
max_requests_jitter = 1000

# Security
limit_request_line = 4094
limit_request_fields = 100
```

### Comando de Ejecución
```bash
# Desarrollo
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000

# Producción
gunicorn app.main:app \
    --workers 4 \
    --worker-class uvicorn.workers.UvicornWorker \
    --bind 0.0.0.0:8000 \
    --timeout 120 \
    --graceful-timeout 30 \
    --keep-alive 5 \
    --access-logfile - \
    --error-logfile - \
    --capture-output
```

### Reglas de Workers
```
┌─────────────────────────────────────────────────────────────┐
│                  Worker Configuration                        │
├─────────────────────────────────────────────────────────────┤
│ CPU-bound (ML inference):    workers = CPU_CORES            │
│ I/O-bound (API calls):       workers = (2 * CPU_CORES) + 1  │
│ Mixed workload:              workers = CPU_CORES + 1        │
│ Kubernetes (1 container):    workers = 1 (scale with pods)  │
└─────────────────────────────────────────────────────────────┘
```

---

## Docker para ML

### Dockerfile Optimizado
```dockerfile
# Dockerfile
FROM python:3.11-slim AS base

# Evitar prompts y bytecode
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /app

# Stage 1: Dependencies
FROM base AS dependencies

# Instalar solo lo necesario para build
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Copiar e instalar dependencies primero (cache layer)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Stage 2: Production
FROM base AS production

# Copiar dependencies instaladas
COPY --from=dependencies /usr/local/lib/python3.11/site-packages /usr/local/lib/python3.11/site-packages
COPY --from=dependencies /usr/local/bin /usr/local/bin

# Crear usuario no-root
RUN useradd --create-home --shell /bin/bash appuser
USER appuser

# Copiar aplicación
COPY --chown=appuser:appuser . .

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8000/health || exit 1

# Puerto
EXPOSE 8000

# Comando producción
CMD ["gunicorn", "app.main:app", \
     "--workers", "4", \
     "--worker-class", "uvicorn.workers.UvicornWorker", \
     "--bind", "0.0.0.0:8000", \
     "--timeout", "120"]
```

### Dockerfile para GPU
```dockerfile
# Dockerfile.gpu
FROM nvidia/cuda:12.1-cudnn8-runtime-ubuntu22.04

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# Python
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.11 \
    python3-pip \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Dependencies con GPU support
COPY requirements-gpu.txt .
RUN pip install --no-cache-dir -r requirements-gpu.txt

COPY . .

EXPOSE 8000

CMD ["gunicorn", "app.main:app", \
     "--workers", "1", \
     "--worker-class", "uvicorn.workers.UvicornWorker", \
     "--bind", "0.0.0.0:8000"]
```

### Docker Compose
```yaml
# docker-compose.yml
version: "3.9"

services:
  api:
    build:
      context: .
      dockerfile: Dockerfile
    ports:
      - "8000:8000"
    environment:
      - MODEL_PATH=/app/models/model.pkl
      - LOG_LEVEL=info
    volumes:
      - ./models:/app/models:ro
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
    deploy:
      resources:
        limits:
          cpus: "2"
          memory: 4G
        reservations:
          cpus: "1"
          memory: 2G
    restart: unless-stopped

  nginx:
    image: nginx:alpine
    ports:
      - "80:80"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
    depends_on:
      - api
    restart: unless-stopped

  prometheus:
    image: prom/prometheus:latest
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml:ro
    restart: unless-stopped
```

### .dockerignore
```
# .dockerignore
__pycache__
*.pyc
*.pyo
*.pyd
.git
.gitignore
.env
.venv
venv
*.egg-info
dist
build
.pytest_cache
.coverage
htmlcov
notebooks/
tests/
*.md
Makefile
docker-compose*.yml
```

---

## ONNX Runtime Optimization

### Exportar PyTorch a ONNX
```python
import torch
import torch.onnx

def export_to_onnx(model, example_input, output_path: str):
    """Exportar modelo PyTorch a ONNX."""
    model.eval()
    
    # PyTorch 2.5+ usa dynamo=True por defecto
    torch.onnx.export(
        model,
        example_input,
        output_path,
        dynamo=True,  # Recomendado 2025
        input_names=["input"],
        output_names=["output"],
        dynamic_axes={
            "input": {0: "batch_size"},
            "output": {0: "batch_size"},
        },
    )
    print(f"Model exported to {output_path}")

# Ejemplo
model = MyModel()
model.load_state_dict(torch.load("model.pth"))
example_input = torch.randn(1, 3, 224, 224)
export_to_onnx(model, example_input, "model.onnx")
```

### Inference con ONNX Runtime
```python
import onnxruntime as ort
import numpy as np

class ONNXInference:
    """High-performance ONNX inference."""
    
    def __init__(self, model_path: str, use_gpu: bool = False):
        # Seleccionar provider
        if use_gpu:
            providers = [
                ("CUDAExecutionProvider", {
                    "device_id": 0,
                    "arena_extend_strategy": "kNextPowerOfTwo",
                    "gpu_mem_limit": 2 * 1024 * 1024 * 1024,  # 2GB
                    "cudnn_conv_algo_search": "EXHAUSTIVE",
                }),
                "CPUExecutionProvider",
            ]
        else:
            providers = ["CPUExecutionProvider"]
        
        # Optimizaciones
        sess_options = ort.SessionOptions()
        sess_options.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL
        sess_options.intra_op_num_threads = 4
        sess_options.inter_op_num_threads = 4
        
        self.session = ort.InferenceSession(
            model_path,
            sess_options=sess_options,
            providers=providers,
        )
        
        self.input_name = self.session.get_inputs()[0].name
        self.output_name = self.session.get_outputs()[0].name
    
    def predict(self, input_data: np.ndarray) -> np.ndarray:
        """Run inference."""
        return self.session.run(
            [self.output_name],
            {self.input_name: input_data.astype(np.float32)},
        )[0]

# Uso
model = ONNXInference("model.onnx", use_gpu=True)
result = model.predict(input_array)
```

### Quantización ONNX
```python
from onnxruntime.quantization import quantize_dynamic, QuantType

def quantize_model(input_path: str, output_path: str):
    """Cuantizar modelo ONNX a INT8."""
    quantize_dynamic(
        model_input=input_path,
        model_output=output_path,
        weight_type=QuantType.QInt8,
    )
    print(f"Quantized model saved to {output_path}")

# Cuantizar
quantize_model("model.onnx", "model_quantized.onnx")
```

### Benchmark ONNX vs PyTorch
```python
import time
import numpy as np

def benchmark_inference(model_fn, input_data, n_runs: int = 100):
    """Benchmark inference latency."""
    # Warmup
    for _ in range(10):
        model_fn(input_data)
    
    # Benchmark
    latencies = []
    for _ in range(n_runs):
        start = time.perf_counter()
        model_fn(input_data)
        latencies.append((time.perf_counter() - start) * 1000)
    
    return {
        "mean_ms": np.mean(latencies),
        "p50_ms": np.percentile(latencies, 50),
        "p95_ms": np.percentile(latencies, 95),
        "p99_ms": np.percentile(latencies, 99),
    }

# Comparar
pytorch_results = benchmark_inference(pytorch_model, input_data)
onnx_results = benchmark_inference(onnx_model.predict, input_data)

print(f"PyTorch: {pytorch_results['p50_ms']:.2f}ms (p50)")
print(f"ONNX:    {onnx_results['p50_ms']:.2f}ms (p50)")
print(f"Speedup: {pytorch_results['p50_ms'] / onnx_results['p50_ms']:.2f}x")
```

---

## Kubernetes Deployment

### Deployment YAML
```yaml
# k8s/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ml-inference-api
  labels:
    app: ml-inference
spec:
  replicas: 3
  selector:
    matchLabels:
      app: ml-inference
  template:
    metadata:
      labels:
        app: ml-inference
    spec:
      containers:
        - name: ml-api
          image: myregistry/ml-api:v1.0.0
          ports:
            - containerPort: 8000
          resources:
            requests:
              cpu: "500m"
              memory: "1Gi"
            limits:
              cpu: "2000m"
              memory: "4Gi"
          env:
            - name: MODEL_PATH
              value: "/models/model.onnx"
            - name: LOG_LEVEL
              value: "info"
          livenessProbe:
            httpGet:
              path: /health
              port: 8000
            initialDelaySeconds: 10
            periodSeconds: 30
            timeoutSeconds: 5
            failureThreshold: 3
          readinessProbe:
            httpGet:
              path: /ready
              port: 8000
            initialDelaySeconds: 5
            periodSeconds: 10
            timeoutSeconds: 3
            failureThreshold: 3
          volumeMounts:
            - name: model-volume
              mountPath: /models
              readOnly: true
      volumes:
        - name: model-volume
          persistentVolumeClaim:
            claimName: model-pvc
---
apiVersion: v1
kind: Service
metadata:
  name: ml-inference-service
spec:
  selector:
    app: ml-inference
  ports:
    - protocol: TCP
      port: 80
      targetPort: 8000
  type: ClusterIP
```

### Horizontal Pod Autoscaler
```yaml
# k8s/hpa.yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: ml-inference-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: ml-inference-api
  minReplicas: 2
  maxReplicas: 10
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
    - type: Resource
      resource:
        name: memory
        target:
          type: Utilization
          averageUtilization: 80
```

### GPU Deployment
```yaml
# k8s/deployment-gpu.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ml-inference-gpu
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ml-inference-gpu
  template:
    spec:
      containers:
        - name: ml-api
          image: myregistry/ml-api:v1.0.0-gpu
          resources:
            limits:
              nvidia.com/gpu: 1
          env:
            - name: CUDA_VISIBLE_DEVICES
              value: "0"
      nodeSelector:
        accelerator: nvidia-tesla-t4
      tolerations:
        - key: nvidia.com/gpu
          operator: Exists
          effect: NoSchedule
```

---

## CI/CD Pipeline

### GitHub Actions
```yaml
# .github/workflows/deploy.yml
name: Build and Deploy ML API

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: "3.11"
      
      - name: Install dependencies
        run: |
          pip install -r requirements.txt
          pip install pytest pytest-cov
      
      - name: Run tests
        run: pytest tests/ --cov=app --cov-report=xml
      
      - name: Upload coverage
        uses: codecov/codecov-action@v4

  build:
    needs: test
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
    
    steps:
      - uses: actions/checkout@v4
      
      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3
      
      - name: Login to Container Registry
        uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      
      - name: Extract metadata
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}
          tags: |
            type=sha,prefix=
            type=ref,event=branch
            type=semver,pattern={{version}}
      
      - name: Build and push
        uses: docker/build-push-action@v5
        with:
          context: .
          push: ${{ github.event_name != 'pull_request' }}
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha
          cache-to: type=gha,mode=max

  deploy:
    needs: build
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    
    steps:
      - uses: actions/checkout@v4
      
      - name: Deploy to Kubernetes
        uses: azure/k8s-deploy@v4
        with:
          manifests: |
            k8s/deployment.yaml
            k8s/service.yaml
            k8s/hpa.yaml
          images: |
            ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }}
```

---

## Monitoring & Observability

### Prometheus Metrics
```python
from prometheus_client import Counter, Histogram, generate_latest
from fastapi import Response

# Métricas
REQUEST_COUNT = Counter(
    "http_requests_total",
    "Total HTTP requests",
    ["method", "endpoint", "status"]
)

REQUEST_LATENCY = Histogram(
    "http_request_duration_seconds",
    "HTTP request latency",
    ["method", "endpoint"],
    buckets=[0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5]
)

PREDICTION_COUNT = Counter(
    "ml_predictions_total",
    "Total predictions made",
    ["model_version", "class"]
)

PREDICTION_LATENCY = Histogram(
    "ml_prediction_duration_seconds",
    "ML prediction latency",
    buckets=[0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25]
)

# Endpoint de métricas
@app.get("/metrics")
async def metrics():
    return Response(
        content=generate_latest(),
        media_type="text/plain"
    )

# Middleware para métricas automáticas
@app.middleware("http")
async def prometheus_middleware(request: Request, call_next):
    start_time = time.perf_counter()
    response = await call_next(request)
    
    REQUEST_COUNT.labels(
        method=request.method,
        endpoint=request.url.path,
        status=response.status_code
    ).inc()
    
    REQUEST_LATENCY.labels(
        method=request.method,
        endpoint=request.url.path
    ).observe(time.perf_counter() - start_time)
    
    return response
```

### Prometheus Config
```yaml
# prometheus.yml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: "ml-api"
    static_configs:
      - targets: ["ml-api:8000"]
    metrics_path: /metrics
```

---

## Security Best Practices

### API Security
```python
from fastapi import Depends, HTTPException, Security
from fastapi.security import APIKeyHeader
import secrets

API_KEY_HEADER = APIKeyHeader(name="X-API-Key")
VALID_API_KEYS = {"key1": "service-a", "key2": "service-b"}

async def verify_api_key(api_key: str = Security(API_KEY_HEADER)):
    if api_key not in VALID_API_KEYS:
        raise HTTPException(status_code=403, detail="Invalid API key")
    return VALID_API_KEYS[api_key]

@app.post("/predict", dependencies=[Depends(verify_api_key)])
async def predict(request: PredictionRequest):
    ...
```

### Rate Limiting
```python
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded

limiter = Limiter(key_func=get_remote_address)
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

@app.post("/predict")
@limiter.limit("100/minute")
async def predict(request: Request, data: PredictionRequest):
    ...
```

### Input Validation
```python
from pydantic import BaseModel, Field, field_validator

class PredictionRequest(BaseModel):
    features: list[float] = Field(..., min_length=4, max_length=4)
    
    @field_validator("features")
    @classmethod
    def validate_features(cls, v):
        for i, val in enumerate(v):
            if not -1000 <= val <= 1000:
                raise ValueError(f"Feature {i} out of range [-1000, 1000]")
        return v
```

---

## Checklist Production

### Pre-Deploy
```
□ Tests pasan (unit, integration)
□ Model validado (accuracy, latency)
□ Dockerfile optimizado (multi-stage, non-root)
□ Health checks configurados (/health, /ready)
□ Logging estructurado
□ Métricas Prometheus expuestas
□ Rate limiting configurado
□ Secrets en env vars (no hardcoded)
□ .dockerignore completo
```

### Infrastructure
```
□ Container registry configurado
□ Kubernetes manifests validados
□ HPA configurado
□ Resource limits definidos
□ PersistentVolume para modelos
□ Ingress/Load balancer configurado
□ TLS/HTTPS habilitado
```

### Monitoring
```
□ Prometheus scraping métricas
□ Grafana dashboards configurados
□ Alertas configuradas (latency, errors)
□ Log aggregation (ELK/Loki)
□ Tracing distribuido (opcional)
```

### Post-Deploy
```
□ Smoke tests ejecutados
□ Latency dentro de SLA
□ Error rate < 0.1%
□ Rollback plan documentado
□ Runbook para incidentes
```

---

## Performance Targets

| Métrica | Target | Critical |
|---------|--------|----------|
| P50 Latency | < 50ms | < 100ms |
| P99 Latency | < 200ms | < 500ms |
| Throughput | > 100 RPS | > 50 RPS |
| Error Rate | < 0.1% | < 1% |
| Availability | > 99.9% | > 99% |

---

## Quick Reference

### Comandos Docker
```bash
# Build
docker build -t ml-api:v1 .

# Run
docker run -p 8000:8000 -e MODEL_PATH=/models/model.pkl ml-api:v1

# Compose
docker compose up -d
docker compose logs -f api

# Debug
docker exec -it <container> /bin/bash
```

### Comandos Kubernetes
```bash
# Apply
kubectl apply -f k8s/

# Scale
kubectl scale deployment ml-inference-api --replicas=5

# Logs
kubectl logs -f deployment/ml-inference-api

# Port forward
kubectl port-forward svc/ml-inference-service 8000:80

# Rollback
kubectl rollout undo deployment/ml-inference-api
```

### Test API
```bash
# Health
curl http://localhost:8000/health

# Predict
curl -X POST http://localhost:8000/predict \
  -H "Content-Type: application/json" \
  -d '{"features": [5.1, 3.5, 1.4, 0.2]}'

# Load test
hey -n 1000 -c 50 -m POST \
  -H "Content-Type: application/json" \
  -d '{"features": [5.1, 3.5, 1.4, 0.2]}' \
  http://localhost:8000/predict
```
