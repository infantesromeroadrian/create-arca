---
name: cicd
description: CI/CD pipeline best practices with GitHub Actions, including testing, building, deploying, and automation. Use when setting up pipelines, optimizing builds, or implementing deployment automation.
paths:
  - ".github/workflows/**"
  - "**/Jenkinsfile"
  - "**/.gitlab-ci.yml"
  - "**/.circleci/**"
  - "**/azure-pipelines.yml"
---

# CI/CD - Best Practices 2025

## Conceptos Core

```
CI (Continuous Integration)
├── Code push → Automatic build
├── Run tests (unit, integration)
├── Code quality checks (lint, format)
└── Security scanning

CD (Continuous Delivery/Deployment)
├── Delivery: Manual trigger to production
└── Deployment: Automatic push to production
```

## GitHub Actions - Versiones Actuales (Enero 2025)

| Action | Versión | Notas |
|--------|---------|-------|
| `actions/checkout` | `v6` | Soporte mejorado para sparse checkout |
| `actions/setup-python` | `v6` | Cache integrado |
| `actions/setup-node` | `v4` | Cache npm/yarn/pnpm |
| `actions/cache` | `v4` | Cache mejorado |
| `astral-sh/setup-uv` | `v7` | Cache automático, Python install |
| `docker/build-push-action` | `v6` | BuildKit mejorado |
| `docker/setup-buildx-action` | `v3` | Multi-platform |

## Workflow Básico - Node.js

```yaml
# .github/workflows/ci.yml
name: CI Pipeline

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      
      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '22'
          cache: 'npm'
      
      - name: Install dependencies
        run: npm ci
      
      - name: Run tests
        run: npm test
      
      - name: Run linter
        run: npm run lint
```

## Python Pipeline con uv (RECOMENDADO)

```yaml
name: Python CI (uv)

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        python-version: ['3.11', '3.12', '3.13']
    
    steps:
      - uses: actions/checkout@v6
      
      - name: Install uv
        uses: astral-sh/setup-uv@v7
        with:
          enable-cache: true
      
      - name: Set up Python ${{ matrix.python-version }}
        run: uv python install ${{ matrix.python-version }}
      
      - name: Install dependencies
        run: uv sync --frozen
      
      - name: Lint with ruff
        run: uv run ruff check .
      
      - name: Format check
        run: uv run ruff format --check .
      
      - name: Type check with mypy
        run: uv run mypy src/
      
      - name: Test with pytest
        run: uv run pytest tests/ --cov=src/ --cov-report=xml
      
      - name: Upload coverage
        uses: codecov/codecov-action@v4
        with:
          files: ./coverage.xml
```

## Python Pipeline con pip (Legacy)

```yaml
name: Python CI (pip)

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        python-version: ['3.11', '3.12', '3.13']
    
    steps:
      - uses: actions/checkout@v6
      
      - name: Setup Python
        uses: actions/setup-python@v6
        with:
          python-version: ${{ matrix.python-version }}
          cache: 'pip'
      
      - name: Install dependencies
        run: |
          python -m pip install --upgrade pip
          pip install -r requirements.txt
          pip install -r requirements-dev.txt
      
      - name: Lint with ruff
        run: ruff check .
      
      - name: Type check with mypy
        run: mypy src/
      
      - name: Test with pytest
        run: pytest tests/ --cov=src/ --cov-report=xml
      
      - name: Upload coverage
        uses: codecov/codecov-action@v4
        with:
          files: ./coverage.xml
```

## Matrix Strategy (Multi-version/Multi-OS)

```yaml
jobs:
  test:
    runs-on: ${{ matrix.os }}
    strategy:
      matrix:
        python-version: ['3.11', '3.12', '3.13']
        os: [ubuntu-latest, macos-latest, windows-latest]
      fail-fast: false  # Continuar si una combinación falla
    
    steps:
      - uses: actions/checkout@v6
      - uses: astral-sh/setup-uv@v7
        with:
          enable-cache: true
      - run: uv python install ${{ matrix.python-version }}
      - run: uv sync --frozen
      - run: uv run pytest
```

## Pipeline Completo (CI + CD)

```yaml
name: CI/CD Pipeline

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}

jobs:
  # ===== CI: Test =====
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - uses: astral-sh/setup-uv@v7
        with:
          enable-cache: true
      - run: uv sync --frozen
      - run: uv run ruff check .
      - run: uv run mypy src/
      - run: uv run pytest tests/ --cov=src/

  # ===== CI: Security Scan =====
  security:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - name: Run Trivy vulnerability scanner
        uses: aquasecurity/trivy-action@master
        with:
          scan-type: 'fs'
          scan-ref: '.'
          severity: 'CRITICAL,HIGH'

  # ===== CI: Build Image =====
  build:
    needs: [test, security]
    runs-on: ubuntu-latest
    outputs:
      image-tag: ${{ steps.meta.outputs.tags }}
    
    steps:
      - uses: actions/checkout@v6
      
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
        uses: docker/build-push-action@v6
        with:
          context: .
          push: ${{ github.event_name != 'pull_request' }}
          tags: ${{ steps.meta.outputs.tags }}
          cache-from: type=gha
          cache-to: type=gha,mode=max

  # ===== CD: Deploy Staging =====
  deploy-staging:
    needs: build
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    environment: staging
    
    steps:
      - name: Deploy to staging
        run: |
          echo "Deploying ${{ needs.build.outputs.image-tag }} to staging"
          # kubectl set image deployment/myapp myapp=${{ needs.build.outputs.image-tag }}

  # ===== CD: Deploy Production =====
  deploy-production:
    needs: [build, deploy-staging]
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    environment:
      name: production
      url: https://myapp.com
    
    steps:
      - name: Deploy to production
        run: |
          echo "Deploying to production"
```

## Environments y Approvals

### Configurar en GitHub
```
Settings → Environments → New environment

staging:
  - No protection rules (auto-deploy)

production:
  - Required reviewers: team-leads
  - Wait timer: 5 minutes
  - Deployment branches: main only
```

### Usar en Workflow
```yaml
jobs:
  deploy:
    environment:
      name: production
      url: https://myapp.com
    runs-on: ubuntu-latest
    steps:
      - name: Deploy
        run: ./deploy.sh
```

## Secrets Management

### Tipos de Secrets
```yaml
# Repository secrets
${{ secrets.API_KEY }}

# Environment secrets (más seguros)
${{ secrets.PROD_API_KEY }}  # Solo disponible en environment 'production'

# Organization secrets
${{ secrets.ORG_NPM_TOKEN }}
```

### Best Practices
```yaml
# [PASS] BUENO: Usar secrets
- name: Deploy
  env:
    API_KEY: ${{ secrets.API_KEY }}
  run: ./deploy.sh

# [FAIL] MALO: Hardcoded
- name: Deploy
  run: API_KEY=secret123 ./deploy.sh

# [PASS] BUENO: Mask en logs
- name: Generate token
  run: |
    TOKEN=$(generate-token)
    echo "::add-mask::$TOKEN"
    echo "TOKEN=$TOKEN" >> $GITHUB_ENV
```

## Caching

### uv Cache (Automático)
```yaml
# astral-sh/setup-uv@v7 tiene cache automático
- uses: astral-sh/setup-uv@v7
  with:
    enable-cache: true
    # cache-dependency-glob: "uv.lock"  # Default
```

### Node.js Cache
```yaml
- uses: actions/setup-node@v4
  with:
    node-version: '22'
    cache: 'npm'
```

### Python pip Cache
```yaml
- uses: actions/setup-python@v6
  with:
    python-version: '3.13'
    cache: 'pip'
```

### Custom Cache
```yaml
- uses: actions/cache@v4
  with:
    path: |
      ~/.cache/pip
      .venv
    key: ${{ runner.os }}-pip-${{ hashFiles('**/requirements.txt') }}
    restore-keys: |
      ${{ runner.os }}-pip-
```

### Docker Layer Caching
```yaml
- name: Build and push
  uses: docker/build-push-action@v6
  with:
    context: .
    push: true
    tags: myapp:latest
    cache-from: type=gha
    cache-to: type=gha,mode=max
```

## Triggers Avanzados

### Path Filters
```yaml
on:
  push:
    paths:
      - 'src/**'
      - 'pyproject.toml'
      - 'uv.lock'
    paths-ignore:
      - 'docs/**'
      - '**.md'
```

### Scheduled Runs
```yaml
on:
  schedule:
    - cron: '0 0 * * *'  # Daily at midnight UTC
    - cron: '0 0 * * 0'  # Weekly on Sunday
```

### Manual Trigger
```yaml
on:
  workflow_dispatch:
    inputs:
      environment:
        description: 'Deployment environment'
        required: true
        default: 'staging'
        type: choice
        options:
          - staging
          - production
      version:
        description: 'Version to deploy'
        required: true
        type: string

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Deploy ${{ inputs.version }} to ${{ inputs.environment }}
        run: ./deploy.sh ${{ inputs.environment }} ${{ inputs.version }}
```

## Reusable Workflows

### Definir Workflow Reusable
```yaml
# .github/workflows/deploy-template.yml
name: Deploy Template

on:
  workflow_call:
    inputs:
      environment:
        required: true
        type: string
      image-tag:
        required: true
        type: string
    secrets:
      DEPLOY_KEY:
        required: true

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: ${{ inputs.environment }}
    steps:
      - name: Deploy
        env:
          DEPLOY_KEY: ${{ secrets.DEPLOY_KEY }}
        run: |
          echo "Deploying ${{ inputs.image-tag }} to ${{ inputs.environment }}"
```

### Usar Workflow Reusable
```yaml
jobs:
  deploy-staging:
    uses: ./.github/workflows/deploy-template.yml
    with:
      environment: staging
      image-tag: ${{ needs.build.outputs.tag }}
    secrets:
      DEPLOY_KEY: ${{ secrets.STAGING_KEY }}
```

## Quality Gates

### PR Checks Required
```yaml
# Branch protection rules en GitHub:
# - Require status checks to pass
# - Require branches to be up to date
# - Required checks: test, lint, security

name: PR Checks

on: pull_request

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - uses: astral-sh/setup-uv@v7
      - run: uv sync --frozen
      - run: uv run pytest

  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - uses: astral-sh/setup-uv@v7
      - run: uv sync --frozen
      - run: uv run ruff check .
      - run: uv run ruff format --check .

  typecheck:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - uses: astral-sh/setup-uv@v7
      - run: uv sync --frozen
      - run: uv run mypy src/

  security:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - uses: astral-sh/setup-uv@v7
      - run: uv sync --frozen
      - run: uv run pip-audit
```

### Coverage Requirements
```yaml
- name: Check coverage
  run: |
    COVERAGE=$(uv run pytest --cov=src --cov-report=term | grep TOTAL | awk '{print $4}' | tr -d '%')
    if [ "$COVERAGE" -lt 80 ]; then
      echo "Coverage $COVERAGE% is below 80%"
      exit 1
    fi
```

## Notifications

### Slack Notification
```yaml
- name: Notify Slack
  if: failure()
  uses: slackapi/slack-github-action@v2
  with:
    channel-id: 'deployments'
    payload: |
      {
        "text": "Deployment failed: ${{ github.workflow }}",
        "blocks": [
          {
            "type": "section",
            "text": {
              "type": "mrkdwn",
              "text": "[FAIL] *Deployment Failed*\n*Workflow:* ${{ github.workflow }}\n*Branch:* ${{ github.ref }}\n*Commit:* ${{ github.sha }}"
            }
          }
        ]
      }
  env:
    SLACK_BOT_TOKEN: ${{ secrets.SLACK_BOT_TOKEN }}
```

## Checklist CI/CD

### CI Mínimo
- [ ] Build automático en push/PR
- [ ] Tests unitarios ejecutados
- [ ] Linter/formatter verificado (ruff)
- [ ] Dependency caching configurado (uv)

### CI Completo
- [ ] Tests de integración
- [ ] Coverage reporting (≥80%)
- [ ] Type checking (mypy --strict)
- [ ] Security scanning (Trivy, pip-audit)
- [ ] Matrix testing (Python versions, OS)
- [ ] PR checks como branch protection

### CD
- [ ] Environments configurados (staging, prod)
- [ ] Secrets por environment
- [ ] Manual approval para producción
- [ ] Rollback strategy definido
- [ ] Notificaciones configuradas
- [ ] Health checks post-deploy

## Anti-patterns

```yaml
# [FAIL] MALO: Secrets en logs
- run: echo ${{ secrets.API_KEY }}

# [PASS] BUENO: Masked
- run: |
    echo "::add-mask::${{ secrets.API_KEY }}"
    ./deploy.sh

# [FAIL] MALO: pip install sin lock
- run: pip install -r requirements.txt

# [PASS] BUENO: uv con lockfile
- run: uv sync --frozen

# [FAIL] MALO: Sin cache
- run: pip install -r requirements.txt

# [PASS] BUENO: Con cache automático
- uses: astral-sh/setup-uv@v7
  with:
    enable-cache: true
- run: uv sync --frozen

# [FAIL] MALO: Deployment sin gates
deploy:
  runs-on: ubuntu-latest
  steps:
    - run: ./deploy-to-prod.sh

# [PASS] BUENO: Con approval
deploy:
  environment:
    name: production
  runs-on: ubuntu-latest
  steps:
    - run: ./deploy-to-prod.sh

# [FAIL] MALO: Versiones sin pinear
- uses: actions/checkout@main

# [PASS] BUENO: Versiones específicas
- uses: actions/checkout@v6
```

## Tools Complementarios

| Función | Herramientas |
|---------|-------------|
| CI/CD | GitHub Actions, GitLab CI, CircleCI |
| Package Manager | uv (recomendado), pip, poetry |
| Linting | ruff (reemplaza flake8+black+isort) |
| Type Check | mypy --strict |
| Security | Trivy, pip-audit, Snyk, Dependabot |
| Coverage | Codecov, Coveralls |
| Artifacts | GitHub Packages, Docker Hub, ghcr.io |
| Notifications | Slack, Discord, Teams |
| IaC | Terraform, Pulumi |
