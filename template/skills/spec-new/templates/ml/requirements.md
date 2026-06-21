---
feature: {{FEATURE}}
slug: {{SLUG}}
type: {{TYPE}}
created: {{DATE}}
status: Draft
owner: ⟦ user_name ⟧ (single-dev)
related_adr: <TODO: ADR-NNN>
triggers_fired: [<TODO: R1 | R2 | R3 | R4>]
---

# Requirements — {{FEATURE}} (ML model)

## 1. ML Problem Statement (mandatory per CLAUDE.md C1)

| Field | Value |
|---|---|
| Task type | <TODO: classification | regression | ranking | forecasting | clustering> |
| Primary metric | <TODO: F1 macro | RMSE | NDCG@10 | MAPE> |
| Target value | <TODO: ≥ 0.85 vs baseline 0.72> |
| Latency SLA (inference) | <TODO: p95 ≤ NN ms> |
| Volume | <TODO: NN predictions/day, peak NN/s> |
| Fairness constraint | <TODO: demographic parity gap ≤ 0.05 across protected attrs A, B> |

## 2. Business goal

<TODO: que problema operacional resuelve el modelo. Coste de no tenerlo. Quien decide si entra a prod.>

## 3. Stakeholders

| Role | Identity | Concern |
|---|---|---|
| Owner | ⟦ user_name ⟧ | <TODO: model en prod en 3 sprints> |
| Domain expert | <TODO: nombre / role> | <TODO: que features tienen sentido, edge cases> |
| Compliance | <TODO: GDPR DPO si Art 22 / EU AI Act notified body si high-risk> | <TODO: explicabilidad, audit trail> |
| Auditor | <TODO> | <TODO: model card, lineage> |
| Maintainer | future-⟦ user_name ⟧ | retraining playbook, drift response |

## 4. Acceptance criteria

- **AC-001** Primary metric ≥ target sobre test set holdout (seed fixed, reproducible).
- **AC-002** Performance no degrada ≥ 5% sobre subgroup minority (fairness gate).
- **AC-003** Inference p95 ≤ SLA bajo carga sostenida.
- **AC-004** Calibration: ECE ≤ 0.05 (si classification).
- **AC-005** SHAP global feature importance disponible; top 5 features tienen sentido para domain expert.
- **AC-006** Drift detection thresholds definidos (KS, Chi², Wasserstein) + alertas configuradas.
- **AC-007** Model card publicado (datasets, metrics, intended use, limitations, ethical considerations).

## 5. Data requirements

| Concern | Spec |
|---|---|
| Source(s) | <TODO: raw paths + schemas> |
| Volume train / val / test | <TODO: NN / NN / NN rows> |
| Features | <TODO: count + types> |
| Target distribution | <TODO: balanced / imbalanced ratio> |
| Sensitive attrs (fairness) | <TODO: gender, race, age, ...> |
| PII (R2 trigger) | <TODO: si | no — si si, GDPR Art 22 aplicable> |
| Temporal split | <TODO: train ≤ T-N días, val (T-N, T-M], test > T-M — sin leakage> |
| Drift baselines | <TODO: stats reference window para drift hook> |

## 6. Non-functional requirements

### 6.1 Performance

- Training time budget: <TODO: NN h en ⟦ gpu ⟧ o NN h en cloud SageMaker>
- Inference latency p50/p95/p99: <TODO: NN/NN/NN ms>
- Memory footprint inference: <TODO: NN MB max> (⟦ gpu ⟧ hard cap si on-prem)
- Throughput: <TODO: NN predictions/s>

### 6.2 Reproducibility

- Seeds fixed: numpy, torch, sklearn, hashlib, random.
- DVC tracking dataset versions.
- MLflow tracking experiments + model registry.
- Container image hash pinned.

### 6.3 Compliance

- GDPR Art 22 (automated decision): <TODO: si | no>. Si si, opt-out endpoint + human review path.
- EU AI Act risk classification: <TODO: high-risk | limited-risk | minimal>. Si high-risk, conformity assessment + technical documentation Art 11.
- SOC 2 lineage: dataset → features → model → predictions traceable.
- Bias audit: fairness metrics across protected attrs, documented quarterly.

### 6.4 Observability

- Prediction drift: KL-divergence sobre output distribution (Prometheus gauge).
- Data drift: KS / Chi² / Wasserstein per feature (Prometheus gauges).
- Concept drift: accuracy en sliding window con ground truth (Prometheus).
- Fairness runtime: per-subgroup metrics gauges.
- Cost per prediction: tag-based attribution.

### 6.5 Reliability

- RTO: <TODO: NN min en caso de model rollback>
- Champion / challenger pattern para retraining.
- Shadow mode 7 dias antes de canary.

## 7. Out of scope

- <TODO: e.g. real-time online learning>
- <TODO: e.g. cross-tenant model sharing>

## 8. References

- ADR linked: `docs/adr/<TODO: NNN-slug.md>`
- Related skill: `mlflow`, `dvc`, `feature-store-feast` (si aplica)
- ARCA agents involucrados: `@data-validator`, `@data-scientist`, `@ml-engineer`, `@math-critic`, `@model-evaluator`, `@mlops-engineer`, `@monitoring`

---

**Spec status:** Draft → completar TODOs antes de promover.
