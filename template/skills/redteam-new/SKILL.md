---
name: redteam-new
description: Pipeline ART de 9 fases (R0-R8) para AI red teaming estructurado con @ai-redteam-orchestrator. MITRE ATLAS + OWASP LLM Top 10:2025. Invócame cuando ⟦ user_name ⟧ diga red team este modelo, /redteam-new <target>, audita este LLM, o similar.
when_to_use: arranque de assessment AI red teaming — adversarial testing de sistema AI/LLM con metodología ATLAS
argument-hint: <target-name>
disable-model-invocation: false
user-invocable: true
allowed-tools: Bash(mkdir *) Bash(ls *) Bash(cat *) Read Grep Glob Write Edit
model: opus
effort: high
paths:
  - "**/redteam/**"
---

# /redteam-new — Pipeline ART 9 fases (ADR-081)

⟦ user_name ⟧ pidió arrancar un AI red team assessment contra: `$ARGUMENTS`.

Master orchestrator: `@ai-redteam-orchestrator`. Enforces 4 blocking gates (R2 threat model, R3 critical injection, R5 ASL escalation, R8 report).

## R0 — Scope & Authorization (este skill cubre R0)

### Step 1: Create directory structure

```bash
TARGET_DIR="redteam"
mkdir -p "$TARGET_DIR/reports"
```

### Step 2: Interactive scope definition

Ask ⟦ user_name ⟧ for each field before writing scope.json:

1. **Target name**: from `$ARGUMENTS` or ask
2. **Model type**: what model/system is being tested (e.g., "claude-sonnet-4-6-via-api", "custom-rag-pipeline", "ollama-qwen-local")
3. **Access level**: `white-box` (weights+code) / `gray-box` (API+docs) / `black-box` (API only)
4. **RoE**: rules of engagement — what is in scope, what is out of scope
5. **Time budget**: default 8 hours, configurable
6. **CVP required**: true if real production system, false if sandbox/local

### Step 3: Write scope.json

```json
{
  "version": "1.0.0",
  "target": "<from step 2>",
  "model_type": "<from step 2>",
  "access_level": "<from step 2>",
  "roe": {
    "in_scope": ["<list>"],
    "out_of_scope": ["<list>"]
  },
  "time_budget_hours": 8,
  "cvp_required": false,
  "cvp_org": "",
  "started_at": "<ISO8601 now>",
  "assessor": "⟦ user_name ⟧"
}
```

### Step 4: Initialize state.json

```json
{
  "version": "1.0.0",
  "target": "<from scope>",
  "model_type": "<from scope>",
  "access_level": "<from scope>",
  "started_at": "<ISO8601>",
  "phase": "R0",
  "roe_signed": false,
  "cvp_required": false,
  "phases_completed": [],
  "phases_skipped": {},
  "findings_summary": {
    "critical": 0,
    "high": 0,
    "medium": 0,
    "low": 0,
    "informational": 0
  },
  "atlas_techniques_tested": [],
  "owasp_llm_tested": [],
  "time_budget_hours": 8,
  "time_spent_hours": 0,
  "tools_used": [],
  "report_path": null
}
```

### Step 5: Gate R0

Ask ⟦ user_name ⟧ to confirm scope:
> "Scope definido para **<target>** (access: <level>, budget: <hours>h). ¿Confirmas RoE y arrancamos R1?"

If ⟦ user_name ⟧ confirms → update `state.json` with `roe_signed: true`, `phases_completed: ["R0"]`, `phase: "R1"`.

### Step 6: Delegate to @ai-redteam-orchestrator

Hand off to `@ai-redteam-orchestrator` with context:
- Target: <name>
- Access: <level>
- Budget: <hours>h
- State: redteam/state.json
- Instruction: proceed to R1 Target Profiling

The orchestrator takes over from R1 onwards. This skill only handles R0 setup.
