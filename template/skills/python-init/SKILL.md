---
name: python-init
description: >
  Initialize Python projects with uv, ruff, mypy, and pytest. Invoke when creating a new
  Python project, setting up a src-layout structure, configuring pyproject.toml, or
  scaffolding hexagonal architecture (domain, application, infrastructure, interfaces).
---

# Python Project Init Skill

## Estructura Estándar
```
proyecto/
├── src/
│   └── proyecto/
│       ├── __init__.py
│       ├── domain/          # Entidades y lógica de negocio
│       ├── application/     # Casos de uso
│       ├── infrastructure/  # Adaptadores externos
│       └── interfaces/      # API, CLI, etc.
├── tests/
│   ├── unit/
│   ├── integration/
│   └── conftest.py
├── pyproject.toml
├── .gitignore
├── .env.example
└── README.md
```

## pyproject.toml Base
```toml
[project]
name = "proyecto"
version = "0.1.0"
requires-python = ">=3.11"
dependencies = []

[project.optional-dependencies]
dev = [
    "pytest>=8.0",
    "pytest-cov>=4.0",
    "mypy>=1.8",
    "ruff>=0.3",
    "hypothesis>=6.0",
]

[tool.ruff]
line-length = 88
target-version = "py311"

[tool.ruff.lint]
select = ["E", "F", "I", "N", "W", "UP", "B", "C4", "SIM"]

[tool.mypy]
strict = true
python_version = "3.11"

[tool.pytest.ini_options]
testpaths = ["tests"]
addopts = "-v --cov=src"
```

## Comandos de Setup
```bash
uv init proyecto
cd proyecto
uv add --dev pytest pytest-cov mypy ruff hypothesis
uv sync
```

## .gitignore Esencial
```
__pycache__/
*.py[cod]
.env
.venv/
*.egg-info/
dist/
.mypy_cache/
.pytest_cache/
.coverage
```
