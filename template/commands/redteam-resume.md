---
description: Resume un AI red team assessment en progreso desde redteam/state.json. Uso, /redteam-resume [dir]. Per ADR-081.
---

# /redteam-resume — Resume Pipeline ART

Retoma un assessment AI Red Teaming en progreso cargando state persistido.

## Usage

```
/redteam-resume
/redteam-resume path/to/redteam
```

## What it does

1. Reads `redteam/state.json` (or custom path)
2. Displays current phase + findings summary
3. Resumes orchestration from last completed phase via `@ai-redteam-orchestrator`
