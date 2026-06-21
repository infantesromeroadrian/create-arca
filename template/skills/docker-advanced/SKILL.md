---
name: docker-advanced
description: Docker best practices for AI/ML workloads, GPU acceleration, security hardening (rootless, seccomp, AppArmor), and production deployment. Use when containerizing ML applications, hardening containers for security, or optimizing Docker for production.
paths:
  - "**/Dockerfile*"
  - "**/docker-compose*.yml"
  - "**/docker-compose*.yaml"
  - "**/.dockerignore"
  - "**/compose.yml"
  - "**/compose.yaml"
---

# Docker - Best Practices 2025 (AI/ML + Security + Production)

## Versiones Actuales (Enero 2025)

| Componente | Versión Estable | Versión Latest |
|------------|-----------------|----------------|
| CUDA | 12.4 | 13.1 |
| cuDNN | 9 | 9 |
| PyTorch | 2.6.0 | 2.7.0 |
| TensorFlow | 2.18.1 | 2.20.0 |
| Python | 3.12 | 3.13 |
| NVIDIA Driver | 550 | 565 |
| Ubuntu | 22.04 LTS | 24.04 LTS |

## GPU & AI/ML Containers

### NVIDIA Container Toolkit Setup
```bash
# 1. Instalar NVIDIA drivers en el host
sudo apt update
sudo apt install nvidia-driver-565  # o 550 para estabilidad
sudo reboot

# 2. Verificar GPU
nvidia-smi

# 3. Instalar NVIDIA Container Toolkit
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
    sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
    sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

sudo apt update
sudo apt install -y nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker

# 4. Test
docker run --rm --gpus all nvidia/cuda:12.4-base-ubuntu22.04 nvidia-smi
```

### Base Images para AI/ML (2025)
```dockerfile
# ===== PyTorch =====
# Docker Hub (estable)
FROM pytorch/pytorch:2.6.0-cuda12.4-cudnn9-runtime
FROM pytorch/pytorch:2.6.0-cuda12.4-cudnn9-devel

# NVIDIA NGC (optimizado, más actualizado)
FROM nvcr.io/nvidia/pytorch:25.04-py3

# ===== TensorFlow =====
# Docker Hub
FROM tensorflow/tensorflow:2.18.1-gpu
FROM tensorflow/tensorflow:latest-gpu-jupyter

# NVIDIA NGC (optimizado)
FROM nvcr.io/nvidia/tensorflow:25.02-tf2-py3

# ===== NVIDIA CUDA base (para custom builds) =====
FROM nvidia/cuda:12.4-devel-ubuntu22.04
FROM nvidia/cuda:12.8-devel-ubuntu24.04
FROM nvidia/cuda:13.1.0-devel-ubuntu24.04  # Última

# ===== Hugging Face =====
FROM huggingface/transformers-pytorch-gpu:latest

# ===== vLLM (LLM Inference) =====
FROM vllm/vllm-openai:latest
```

### Dockerfile ML Production (con uv)
```dockerfile
# ===== STAGE 1: Build =====
FROM nvidia/cuda:12.4-devel-ubuntu22.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive

# Instalar Python y uv
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.12 \
    python3.12-dev \
    python3.12-venv \
    curl \
    git \
    build-essential \
    && rm -rf /var/lib/apt/lists/* \
    && ln -s /usr/bin/python3.12 /usr/bin/python

# Instalar uv (RECOMENDADO sobre pip)
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
ENV PATH="/root/.local/bin:$PATH"

WORKDIR /app

# Copiar dependencias
COPY pyproject.toml uv.lock ./

# Instalar dependencias con uv (10-100x más rápido que pip)
RUN uv sync --frozen --no-dev

# ===== STAGE 2: Runtime =====
FROM nvidia/cuda:12.4-runtime-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

# Runtime mínimo
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.12 \
    && rm -rf /var/lib/apt/lists/* \
    && ln -s /usr/bin/python3.12 /usr/bin/python

# Copiar venv desde builder
COPY --from=builder /app/.venv /app/.venv
ENV PATH="/app/.venv/bin:$PATH"

# Usuario no-root (SEGURIDAD)
RUN useradd -m -u 1000 -s /bin/bash mluser
WORKDIR /app
RUN chown -R mluser:mluser /app

# Variables CUDA
ENV NVIDIA_VISIBLE_DEVICES=all
ENV NVIDIA_DRIVER_CAPABILITIES=compute,utility

# Optimización de memoria para LLMs
ENV PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True
ENV TRANSFORMERS_CACHE=/app/cache
ENV HF_HOME=/app/cache

# Copiar código
COPY --chown=mluser:mluser src/ ./src/

USER mluser

# Health check
HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
    CMD python -c "import torch; assert torch.cuda.is_available()" || exit 1

CMD ["python", "-m", "src.main"]
```

### Dockerfile ML Production (con pip - legacy)
```dockerfile
# ===== STAGE 1: Build =====
FROM nvidia/cuda:12.4-devel-ubuntu22.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.12 \
    python3.12-pip \
    python3.12-dev \
    python3.12-venv \
    git \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

RUN ln -s /usr/bin/python3.12 /usr/bin/python

WORKDIR /app

# Virtual environment
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Instalar dependencias (cache-friendly)
COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip wheel && \
    pip install --no-cache-dir -r requirements.txt

# ===== STAGE 2: Runtime =====
FROM nvidia/cuda:12.4-runtime-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.12 \
    && rm -rf /var/lib/apt/lists/* \
    && ln -s /usr/bin/python3.12 /usr/bin/python

# Copiar venv desde builder
COPY --from=builder /opt/venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Usuario no-root (SEGURIDAD)
RUN useradd -m -u 1000 -s /bin/bash mluser
WORKDIR /app
RUN chown -R mluser:mluser /app

# Variables CUDA
ENV NVIDIA_VISIBLE_DEVICES=all
ENV NVIDIA_DRIVER_CAPABILITIES=compute,utility

# Optimización de memoria para LLMs
ENV PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True
ENV TRANSFORMERS_CACHE=/app/cache
ENV HF_HOME=/app/cache

COPY --chown=mluser:mluser . .

USER mluser

HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
    CMD python -c "import torch; assert torch.cuda.is_available()" || exit 1

CMD ["python", "main.py"]
```

### Ejecutar Contenedor con GPU
```bash
# Todas las GPUs
docker run --gpus all -it myml:latest

# GPU específica
docker run --gpus '"device=0"' -it myml:latest

# Múltiples GPUs
docker run --gpus '"device=0,1"' -it myml:latest

# Con shared memory para PyTorch/NCCL (IMPORTANTE para multi-GPU)
docker run --gpus all --shm-size=8g -it myml:latest

# Completo para producción
docker run -d \
    --gpus all \
    --shm-size=8g \
    --memory=32g \
    --cpus=8 \
    -v /data/models:/app/models:ro \
    -p 8000:8000 \
    --name ml-inference \
    myml:latest
```

---

## Security Hardening (CRÍTICO)

### Niveles de Seguridad
```
┌────────────────────────────────────────────────────────────┐
│ Level │ Medida                    │ Reducción Ataque     │
├────────────────────────────────────────────────────────────┤
│   1   │ Non-root user             │ 40%                  │
│   2   │ Read-only filesystem      │ +15%                 │
│   3   │ Seccomp profile           │ +20%                 │
│   4   │ AppArmor/SELinux          │ +15%                 │
│   5   │ Rootless Docker           │ +10%                 │
│ TOTAL │ Todas las medidas         │ ~80% reducción       │
└────────────────────────────────────────────────────────────┘
```

### 1. Non-Root User (OBLIGATORIO)
```dockerfile
# [FAIL] MALO: root por defecto
FROM python:3.13-slim
WORKDIR /app
COPY . .
CMD ["python", "main.py"]

# [PASS] BUENO: usuario no-root
FROM python:3.13-slim
WORKDIR /app

# Crear usuario sin privilegios
RUN groupadd -r appgroup && \
    useradd -r -g appgroup -d /app -s /sbin/nologin appuser

COPY --chown=appuser:appgroup . .

USER appuser
CMD ["python", "main.py"]
```

### 2. Read-Only Filesystem
```bash
# Runtime read-only
docker run --read-only \
    --tmpfs /tmp:rw,noexec,nosuid,size=100m \
    --tmpfs /app/cache:rw,size=500m \
    myapp:latest
```

```yaml
# compose.yml
services:
  app:
    image: myapp:latest
    read_only: true
    tmpfs:
      - /tmp:size=100m
      - /app/cache:size=500m
```

### 3. Seccomp Profiles
```bash
# Ver syscalls usadas por app (para crear perfil custom)
strace -c -f python main.py

# Ejecutar con perfil default (ya activo por defecto)
docker run --security-opt seccomp=default myapp:latest

# Perfil custom restrictivo
docker run --security-opt seccomp=/path/to/seccomp-profile.json myapp:latest
```

```json
// seccomp-ml-profile.json (ejemplo para ML inference)
{
  "defaultAction": "SCMP_ACT_ERRNO",
  "architectures": ["SCMP_ARCH_X86_64"],
  "syscalls": [
    {
      "names": [
        "read", "write", "open", "close", "stat", "fstat",
        "mmap", "mprotect", "munmap", "brk",
        "rt_sigaction", "rt_sigprocmask",
        "ioctl", "access", "pipe", "select", "sched_yield",
        "clone", "fork", "execve", "exit", "wait4",
        "futex", "set_robust_list", "get_robust_list",
        "socket", "connect", "sendto", "recvfrom", "bind", "listen", "accept"
      ],
      "action": "SCMP_ACT_ALLOW"
    }
  ]
}
```

### 4. AppArmor
```bash
# Ver perfil actual
docker inspect --format='{{.HostConfig.SecurityOpt}}' container_name

# Usar perfil AppArmor custom
docker run --security-opt apparmor=my-custom-profile myapp:latest

# Generar perfil con aa-genprof
sudo aa-genprof /path/to/app
```

### 5. Rootless Docker
```bash
# Instalar rootless
curl -fsSL https://get.docker.com/rootless | sh

# Agregar a .bashrc
export PATH=/home/$USER/bin:$PATH
export DOCKER_HOST=unix:///run/user/$(id -u)/docker.sock

# Iniciar
systemctl --user start docker

# Verificar
docker info | grep -i root
# Rootless: true
```

### 6. Capabilities (Drop ALL)
```bash
# Eliminar TODAS las capabilities
docker run --cap-drop=ALL myapp:latest

# Solo agregar las necesarias
docker run --cap-drop=ALL --cap-add=NET_BIND_SERVICE myapp:latest
```

```yaml
# compose.yml
services:
  app:
    image: myapp:latest
    cap_drop:
      - ALL
    cap_add:
      - NET_BIND_SERVICE  # Solo si necesita puerto < 1024
```

### 7. No New Privileges
```bash
docker run --security-opt=no-new-privileges:true myapp:latest
```

```yaml
services:
  app:
    security_opt:
      - no-new-privileges:true
```

### Contenedor Hardened Completo
```bash
docker run -d \
    --name secure-app \
    --user 1000:1000 \
    --read-only \
    --tmpfs /tmp:rw,noexec,nosuid,size=100m \
    --cap-drop=ALL \
    --security-opt=no-new-privileges:true \
    --security-opt seccomp=/etc/docker/seccomp-default.json \
    --security-opt apparmor=docker-default \
    --memory=512m \
    --cpus=1 \
    --pids-limit=100 \
    --network=app-network \
    myapp:latest
```

---

## Image Security Scanning

### Trivy (Recomendado)
```bash
# Instalar
curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin

# Scan básico
trivy image myapp:latest

# Solo CRITICAL y HIGH
trivy image --severity CRITICAL,HIGH myapp:latest

# Formato JSON para CI/CD
trivy image -f json -o results.json myapp:latest

# Fail si hay vulnerabilidades críticas (para CI)
trivy image --exit-code 1 --severity CRITICAL myapp:latest

# Scan de filesystem (antes de build)
trivy fs --security-checks vuln,config .
```

### Docker Scout
```bash
# Incluido en Docker Desktop
docker scout cves myapp:latest

# Quickview
docker scout quickview myapp:latest

# Recomendaciones
docker scout recommendations myapp:latest
```

### En CI/CD (GitHub Actions)
```yaml
- name: Scan image
  uses: aquasecurity/trivy-action@master
  with:
    image-ref: myapp:latest
    format: 'sarif'
    output: 'trivy-results.sarif'
    severity: 'CRITICAL,HIGH'

- name: Upload results
  uses: github/codeql-action/upload-sarif@v3
  with:
    sarif_file: 'trivy-results.sarif'
```

---

## Multi-Stage Builds (con uv)

### Patrón Óptimo
```dockerfile
# ===== Stage 1: Dependencies (uv) =====
FROM python:3.13-slim AS deps

# Instalar uv
RUN pip install uv

WORKDIR /app
COPY pyproject.toml uv.lock ./

# Crear venv y instalar deps
RUN uv sync --frozen --no-dev

# ===== Stage 2: Build (si hay compilación) =====
FROM python:3.13-slim AS builder
WORKDIR /app
COPY --from=deps /app/.venv /app/.venv
ENV PATH="/app/.venv/bin:$PATH"
COPY . .
RUN python -m compileall src/

# ===== Stage 3: Runtime (mínimo) =====
FROM python:3.13-slim AS runtime

# Security: non-root user
RUN useradd -r -u 1000 appuser
WORKDIR /app

# Solo lo necesario
COPY --from=deps /app/.venv /app/.venv
COPY --from=builder /app/src /app/src
ENV PATH="/app/.venv/bin:$PATH"

# Permisos
RUN chown -R appuser:appuser /app
USER appuser

# Metadata
LABEL org.opencontainers.image.title="MyApp" \
      org.opencontainers.image.version="1.0.0"

HEALTHCHECK --interval=30s --timeout=10s CMD python -c "print('ok')" || exit 1

CMD ["python", "-m", "src.main"]
```

---

## Docker Compose Production (2025)

```yaml
# compose.prod.yml (sin 'version:' - deprecated)

services:
  ml-api:
    build:
      context: .
      dockerfile: Dockerfile
      target: runtime
    image: mycompany/ml-api:${VERSION:-latest}
    
    # GPU
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: 1
              capabilities: [gpu]
        limits:
          cpus: '4'
          memory: 16G
    
    # Security
    user: "1000:1000"
    read_only: true
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    tmpfs:
      - /tmp:size=100m
      - /app/cache:size=1g
    
    # Runtime
    environment:
      - NVIDIA_VISIBLE_DEVICES=all
      - PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True
    env_file:
      - .env.prod
    
    # Shared memory para PyTorch (CRÍTICO para multi-GPU)
    shm_size: 8g
    
    # Networking
    ports:
      - "8000:8000"
    networks:
      - app-net
    
    # Health
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s
    
    # Logging
    logging:
      driver: "json-file"
      options:
        max-size: "100m"
        max-file: "5"
    
    # Restart policy
    restart: unless-stopped
    
    volumes:
      - models:/app/models:ro
      - ./logs:/app/logs:rw

  redis:
    image: redis:7-alpine
    user: "999:999"
    read_only: true
    volumes:
      - redis-data:/data
    networks:
      - app-net
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]

volumes:
  models:
    external: true
  redis-data:

networks:
  app-net:
    driver: bridge
```

---

## Secrets Management

### Docker Secrets (Swarm/Compose)
```yaml
# compose.yml
secrets:
  db_password:
    file: ./secrets/db_password.txt
  api_key:
    external: true  # Creado con: docker secret create api_key ./api_key.txt

services:
  app:
    image: myapp:latest
    secrets:
      - db_password
      - api_key
    environment:
      - DB_PASSWORD_FILE=/run/secrets/db_password
```

```python
# app.py - Leer secret
import os

def get_secret(name):
    secret_path = f"/run/secrets/{name}"
    if os.path.exists(secret_path):
        with open(secret_path, 'r') as f:
            return f.read().strip()
    return os.environ.get(name.upper())

db_password = get_secret('db_password')
```

### BuildKit Secrets (Build-time)
```dockerfile
# syntax=docker/dockerfile:1

FROM python:3.13-slim

# Secret disponible solo durante build, NO en imagen final
RUN --mount=type=secret,id=pip_token \
    pip install --extra-index-url https://$(cat /run/secrets/pip_token)@pypi.mycompany.com/simple mypackage
```

```bash
# Build con secret
DOCKER_BUILDKIT=1 docker build \
    --secret id=pip_token,src=./pip_token.txt \
    -t myapp:latest .
```

---

## Monitoring & Runtime Security

### Falco (Runtime Threat Detection)
```bash
# Instalar Falco
curl -fsSL https://falco.org/repo/falcosecurity-packages.asc | \
    sudo gpg --dearmor -o /usr/share/keyrings/falco-archive-keyring.gpg

sudo apt update
sudo apt install -y falco

# Reglas custom para containers
# /etc/falco/rules.d/custom.yaml
- rule: Shell in Container
  desc: Detect shell execution in container
  condition: container and proc.name in (bash, sh, zsh)
  output: "Shell executed in container (user=%user.name container=%container.name)"
  priority: WARNING
```

### GPU Monitoring
```bash
# DCGM Exporter para Prometheus
docker run -d \
    --gpus all \
    --name dcgm-exporter \
    -p 9400:9400 \
    nvcr.io/nvidia/k8s/dcgm-exporter:3.3.5-3.4.0-ubuntu22.04
```

---

## Checklists

### Pre-Build
- [ ] Base image slim/alpine/distroless
- [ ] Version pinning (no :latest en producción)
- [ ] Multi-stage build implementado
- [ ] .dockerignore completo
- [ ] Non-root user definido
- [ ] HEALTHCHECK incluido
- [ ] uv en lugar de pip (si posible)

### Security
- [ ] Trivy scan sin CRITICAL/HIGH
- [ ] Secrets NO en imagen
- [ ] --cap-drop=ALL aplicado
- [ ] Read-only filesystem si posible
- [ ] Seccomp profile activo
- [ ] no-new-privileges habilitado

### AI/ML Específico
- [ ] NVIDIA Container Toolkit configurado
- [ ] --shm-size apropiado (8g+ para multi-GPU)
- [ ] CUDA version compatible con driver
- [ ] Cache directories configurados (HF_HOME, etc.)
- [ ] Memory limits apropiados
- [ ] PYTORCH_CUDA_ALLOC_CONF configurado

### Production
- [ ] Resource limits (memory, CPU, PIDs)
- [ ] Health checks configurados
- [ ] Logging configurado (no stdout infinito)
- [ ] Restart policy definida
- [ ] Network isolation
- [ ] Sin `version:` en compose.yml (deprecated)

---

## Quick Reference

```bash
# Build con BuildKit
DOCKER_BUILDKIT=1 docker build -t myapp .

# Run seguro mínimo
docker run --rm -it \
    --user 1000:1000 \
    --cap-drop=ALL \
    --security-opt=no-new-privileges:true \
    myapp:latest

# Run ML con GPU
docker run --rm -it \
    --gpus all \
    --shm-size=8g \
    --user 1000:1000 \
    myml:latest

# Scan de seguridad
trivy image --severity HIGH,CRITICAL myapp:latest

# Analizar layers
dive myapp:latest

# Benchmark seguridad host
docker run --rm -it \
    --net host --pid host \
    -v /var/run/docker.sock:/var/run/docker.sock \
    docker/docker-bench-security

# Compose (sin version deprecated)
docker compose -f compose.prod.yml up -d
```

## Anti-patterns

```dockerfile
# [FAIL] MALO: Imagen sin version
FROM python:latest

# [PASS] BUENO: Version específica
FROM python:3.13-slim

# [FAIL] MALO: Root user
USER root

# [PASS] BUENO: Non-root
USER appuser

# [FAIL] MALO: pip install sin cache control
RUN pip install -r requirements.txt

# [PASS] BUENO: uv con lockfile
RUN uv sync --frozen

# [FAIL] MALO: Copiar todo
COPY . .

# [PASS] BUENO: Solo lo necesario
COPY --chown=appuser:appuser src/ ./src/

# [FAIL] MALO: CUDA version antigua
FROM nvidia/cuda:11.8-devel-ubuntu20.04

# [PASS] BUENO: CUDA actualizado
FROM nvidia/cuda:12.4-devel-ubuntu22.04
```
