---
name: redteam-resume
description: Resume un AI red team assessment en progreso desde redteam/state.json. Invócame cuando ⟦ user_name ⟧ diga /redteam-resume, continúa el red team, retoma el assessment, o similar.
when_to_use: retomar assessment AI red teaming en progreso con state persistido
argument-hint: "[dir]"
disable-model-invocation: false
user-invocable: true
allowed-tools: Bash(ls *) Bash(cat *) Read Grep Glob Write Edit
model: opus
effort: high
paths:
  - "**/redteam/**"
---

# /redteam-resume — Resume Pipeline ART (ADR-081)

⟦ user_name ⟧ pidió retomar un AI red team assessment. Directorio opcional: `$ARGUMENTS` (default: `redteam/`).

## Step 1: Load state

```bash
STATE_FILE="${ARGUMENTS:-redteam}/state.json"
cat "$STATE_FILE"
```

If state.json does not exist → abort: "No hay assessment en progreso. Usa /redteam-new <target> para empezar uno."

## Step 2: Display summary to ⟦ user_name ⟧

```
═══════════════════════════════════════════════════════
[PIPELINE RT] Resume — <target>
═══════════════════════════════════════════════════════
Target:     <target> (<model_type>)
Access:     <access_level>
Phase:      <current phase>
Started:    <started_at>
Time:       <spent>h / <budget>h

Phases completed: R0, R1, R2, ...
Phases skipped:   R4 (reason: ...)

Findings:   N critical, N high, N medium, N low
ATLAS:      N techniques tested
OWASP LLM:  N/10 covered
═══════════════════════════════════════════════════════
```

## Step 3: Confirm resume

> "Assessment de **<target>** en fase **<phase>**. ¿Continúo desde aquí?"

If ⟦ user_name ⟧ confirms → delegate to `@ai-redteam-orchestrator` with full state context.

## Step 4: Delegate to @ai-redteam-orchestrator

Hand off with:
- Full state.json content
- Current phase to resume from
- Artifacts already produced (list files in redteam/)
- Remaining time budget

The orchestrator picks up from the current phase and continues the pipeline.
