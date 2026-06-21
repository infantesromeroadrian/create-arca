---
description: Inicia Pipeline ART (AI Red Teaming) de 9 fases (R0-R8) con @ai-redteam-orchestrator. MITRE ATLAS + OWASP LLM Top 10:2025. Uso, /redteam-new <target-name>. Per ADR-081.
---

# /redteam-new — Pipeline ART

Arranca el pipeline AI Red Teaming de 9 fases con `@ai-redteam-orchestrator` como master.

## Usage

```
/redteam-new client-chatbot-v2
/redteam-new ollama-qwen-local
/redteam-new rag-pipeline-staging
```

## What it does

1. Creates `redteam/` directory structure
2. Interactive scope definition (target, access level, budget, RoE)
3. Writes `redteam/scope.json` + `redteam/state.json`
4. Hands off to `@ai-redteam-orchestrator` at R0

## Phases

R0 Scope → R1 Profile → R2 Threat Model → R3 Prompt Security → R4 Adversarial ML → R5 Dangerous Caps → R6 Alignment → R7 Defense Validation → R8 Report
