---
feature: {{FEATURE}}
slug: {{SLUG}}
type: {{TYPE}}
created: {{DATE}}
status: Draft
related_adr: <TODO: ADR-NNN>
---

# Tasks — {{FEATURE}} (ML model)

> Mapeado a ARCA Pipeline v4.0. ML training tiene gates math-critic obligatorios (CLAUDE.md mandate sobre @ml-engineer/@dl-engineer producing code).

## Cycle mapping

| Cycle | Tasks |
|---|---|
| C1 Discovery | T-001 |
| C2 Data | T-002, T-003 |
| C3 Hypothesis & Feature | T-004, T-005 |
| C4 Design | T-006 |
| C5 POC | T-007 |
| C6 Build | T-008, T-009, T-010 |
| C7 MLOps | T-011 |
| C8 Quality | T-012, T-013 |
| C9 Pre-prod | T-014 |
| C10 Deploy | T-015 |
| C11 Post-deploy | T-016 |
| C12 Monitoring | T-017 |
| C13 Governance & Loop | T-018 |

## Tasks

### T-001 — Requirements firmados + ML Problem Statement

- **Cycle:** C1 · **Owner:** `@project-planner` · **Effort:** 2h
- Completar `requirements.md` §1 ML Problem Statement (no opcional CLAUDE.md).
- **Gate:** `@project-planner` sign-off + ⟦ user_name ⟧.

### T-002 — Data validation gate (BLOQUEANTE)

- **Cycle:** C2 · **Owner:** `@data-validator` · **Effort:** 3h · **Depends:** T-001
- Audit: temporal leakage, duplicates cross-split, drift baselines, missing patterns MNAR, subgroup coverage.
- **Gate:** `@data-validator` sign-off (BLOQUEANTE — sin esto C2 no cierra).

### T-003 — EDA + feature exploration

- **Cycle:** C2/C3 · **Owner:** `@data-scientist` · **Effort:** 5h · **Depends:** T-002
- EDA solo sobre TRAIN (nunca test). Feature importance baseline (SHAP).
- **Gate:** `@data-scientist` sign-off.

### T-004 — Hypothesis testing

- **Cycle:** C3 · **Owner:** `@data-scientist` + `@math-critic` · **Effort:** 3h · **Depends:** T-003
- Hipotesis estadisticas con tests, IC, effect sizes. NO p-hacking.
- **Gate:** `@math-critic` validacion estadistica.

### T-005 — Feature engineering spec

- **Cycle:** C3 · **Owner:** `@data-scientist` · **Effort:** 3h · **Depends:** T-004
- Pipeline reproducible. Sin leakage cross-split en transformaciones.

### T-006 — Architecture + ADR

- **Cycle:** C4 · **Owner:** `@architect-ai` · **Effort:** 4h · **Depends:** T-005
- ADR firmado, design.md TODOs cerrados, Excalidraw producido.
- **Gate:** `@architect-ai` sign-off.

### T-007 — POC end-to-end minimal

- **Cycle:** C5 · **Owner:** `@ml-engineer` o `@dl-engineer` · **Effort:** 6h · **Depends:** T-006
- Minimal viable training + eval vs baseline. Decide go / no-go.
- **Gate:** Improvement ≥ 5% sobre strong baseline o abort.

### T-008 — Training pipeline production-grade

- **Cycle:** C6 · **Owner:** `@ml-engineer` o `@dl-engineer` · **Effort:** 8h · **Depends:** T-007
- Reproducible (seeds fixed), MLflow tracking, DVC versioning, hyperparameter tuning Optuna, calibracion.
- **Gate:** `@math-critic` (loss / gradients / numerical stability) → `@code-critic`.

### T-009 — Calibration + uncertainty

- **Cycle:** C6 · **Owner:** `@ml-engineer` · **Effort:** 3h · **Depends:** T-008
- ECE ≤ 0.05 si classification. Calibration plot.
- **Gate:** `@math-critic`.

### T-010 — SHAP / explainability

- **Cycle:** C6 · **Owner:** `@ml-engineer` + `@data-scientist` · **Effort:** 2h · **Depends:** T-008
- SHAP global + local. Top features tienen sentido para domain expert.

### T-011 — Model registry + champion/challenger

- **Cycle:** C7 · **Owner:** `@mlops-engineer` · **Effort:** 4h · **Depends:** T-008
- MLflow Model Registry, 4-eyes approval workflow, lineage trail (DVC + OpenLineage).
- **Gate:** `@mlops-engineer` sign-off.

### T-012 — Tests coverage ≥ 80%

- **Cycle:** C8 · **Owner:** `@tester` · **Effort:** 4h · **Depends:** T-008..T-010
- Unit (transforms, preprocessing), integration (pipeline end-to-end), property tests (hypothesis lib).
- **Gate:** `@tester` (BLOQUEANTE).

### T-013 — Model evaluation final

- **Cycle:** C8 · **Owner:** `@model-evaluator` + `@math-critic` · **Effort:** 4h · **Depends:** T-012
- Metrics + CV robusta + SHAP + fairness por subgrupo + drift baseline + production-readiness.
- **Gate:** `@model-evaluator` sign-off (BLOQUEANTE C8 → C9).

### T-014 — Pre-prod validation (shadow mode)

- **Cycle:** C9 · **Owner:** `@deployment` + `@mlops-engineer` · **Effort:** 5h · **Depends:** T-013
- Shadow 7d en staging. Latency p95 SLA. Load test.
- **Gate:** `@deployment` sign-off.

### T-015 — Production deploy con canary

- **Cycle:** C10 · **Owner:** `@deployment` + `@chief-architect` · **Effort:** 4h · **Depends:** T-014
- Canary 5% → 25% → 50% → 100% con auto-rollback en SLO degradation. Rollback ≤5 min testado.
- **Gate:** `@chief-architect` (BLOQUEANTE C10).

### T-016 — Post-deploy smoke + A/B

- **Cycle:** C11 · **Owner:** `@deployment` + `@monitoring` · **Effort:** 2h · **Depends:** T-015
- Smoke test golden path. Verificar A/B test stats si aplica.

### T-017 — Drift + fairness monitoring

- **Cycle:** C12 · **Owner:** `@monitoring` · **Effort:** 3h · **Depends:** T-016
- Drift dashboards (data + prediction + concept). Fairness per subgroup. Alerts con runbooks.
- **Gate:** `@monitoring` sign-off.

### T-018 — Governance trail + retraining trigger

- **Cycle:** C13 · **Owner:** `@mlops-engineer` · **Effort:** 3h · **Depends:** T-017
- Audit trail (lineage). EU AI Act Art 11 technical doc. Retraining trigger configured (drift threshold + scheduled).

## Total effort estimate

<TODO: sum effort. Ballpark: 2+3+5+3+3+4+6+8+3+2+4+4+4+5+4+2+3+3 = 68h>

## Risks during execution

| Risk | Likelihood | Mitigation |
|---|---|---|
| Data validation gate falla (temporal leakage) | M | Re-split, no avanzar a C3 |
| `@math-critic` rejecta T-008 dos veces | M | Escalar `@architect-ai` (max 2 cycles) |
| Calibration ECE > 0.05 sin remedio | L | Aceptar deuda + ticket calibrar v1.1 |
| Fairness gap > threshold | M | Re-balance training set o constrained optimization |
| Concept drift en producion antes del 30d | L | Champion/challenger setup + retraining trigger |

## Status tracking

Estado en Obsidian `Projects/<project>/Status.md`. Re-hash `spec.lock.json` al completar tasks (S4 deliverable).
