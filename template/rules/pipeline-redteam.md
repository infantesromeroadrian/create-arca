---
description: AI Red Teaming Pipeline ART — auto-loaded when touching **/redteam/** paths
globs:
  - "**/redteam/**"
---

# Pipeline ART — AI Red Teaming (ADR-081)

9-phase structured adversarial testing of AI/LLM systems.
Orchestrator: `@ai-redteam-orchestrator`. Activation: `/redteam-new <target>` or `/redteam-resume`.

## Phases

| Phase | Owner | Artifact | Gate |
|---|---|---|---|
| R0 Scope & Auth | `@ai-redteam-orchestrator` | `redteam/scope.json` | Scope signed by ⟦ user_name ⟧ |
| R1 Target Profile | `@ai-red-teamer` | `redteam/profile.json` | — |
| R2 Threat Model | `@ai-red-teamer` + `@architect-ai` | `redteam/threat-model.md` | **BLOQUEANTE** — ⟦ user_name ⟧ reviews |
| R3 Prompt Security | `@ai-red-teamer` | `redteam/prompt-security-findings.json` | **BLOQUEANTE** — critical = halt |
| R4 Adversarial ML | `@ai-red-teamer` | `redteam/adversarial-ml-findings.json` | Skippable (document reason) |
| R5 Dangerous Caps | `@evals-engineer` | `redteam/dangerous-caps-eval.json` | **BLOQUEANTE** — ASL-3+ = escalate. Skippable if not frontier. |
| R6 Alignment | `@alignment-researcher` | `redteam/alignment-findings.json` | — |
| R7 Defense Valid | `@trust-and-safety-engineer` | `redteam/defense-validation-findings.json` | — |
| R8 Report | `@ai-red-teamer` + `@docs-writer` | `redteam/reports/<target>-<date>.md` | **BLOQUEANTE** — ⟦ user_name ⟧ reviews |

## Gate chain

R0 (scope) → R1 → R2 (threat model) → R3 (critical halt) → R4 (skip?) → R5 (ASL gate, skip?) → R6 → R7 → R8 (report) → DONE

## Directory structure

```
redteam/
├── scope.json
├── profile.json
├── threat-model.md
├── prompt-security-findings.json
├── adversarial-ml-findings.json
├── dangerous-caps-eval.json
├── alignment-findings.json
├── defense-validation-findings.json
├── state.json
└── reports/
    └── <target>-<date>.md
```

## Rules

- No phase advances without artifact written.
- 4 blocking gates are NON-NEGOTIABLE.
- Skipped phases MUST document reason in state.json.
- Every finding MUST have: ATLAS technique ID + CVSS v4.0 + CWE + PoC.
- Default time budget: 8 hours. R3 gets 35%.
- State persists in `redteam/state.json` — `/redteam-resume` loads it.
- Pipeline ART state is ISOLATED from ML (`loot/`) and HTB (`loot/`) state.
