---
feature: {{FEATURE}}
slug: {{SLUG}}
type: {{TYPE}}
created: {{DATE}}
status: Draft
related_adr: <TODO: ADR-NNN>
related_excalidraw: <TODO: docs/architecture/{{SLUG}}.excalidraw>
---

# Design — {{FEATURE}} (ML model)

> Decisiones arquitecturales viven en `docs/adr/NNN-{{SLUG}}.md`. Este archivo NO duplica — linkea.

## 1. Architecture summary

<TODO: 1 parrafo. Pipeline: data → features → train → eval → registry → serve → monitor.>

Reference: [ADR-NNN](../../adr/NNN-{{SLUG}}.md)
Diagrama: [{{SLUG}}.excalidraw](../../architecture/{{SLUG}}.excalidraw)

## 2. Components affected

| Component | Type | Action | Owner agent |
|---|---|---|---|
| `data/raw/{{SLUG}}/` | Dataset | Source | `@data-engineer` |
| `data/clean/{{SLUG}}/` | Curated | Transform | `@data-engineer` |
| `features/{{SLUG}}/` | Feature engineering | Create | `@data-scientist` |
| `notebooks/eda_{{SLUG}}.ipynb` | EDA | Create | `@data-scientist` |
| `pipelines/train_{{SLUG}}.py` | Training | Create | `@ml-engineer` o `@dl-engineer` |
| `models/{{SLUG}}/` | Trained artifact | Register | `@mlops-engineer` (MLflow) |
| `serving/{{SLUG}}.py` | Inference | Create | `@deployment` o `@ai-production-engineer` |
| `tests/ml/test_{{SLUG}}.py` | Tests | Create | `@tester` |
| `grafana/dashboards/ml_{{SLUG}}.json` | Drift + perf dashboard | Create | `@monitoring` (via Grafana MCP) |

## 3. Data pipeline

### 3.1 Sourcing

<TODO: paths origen, frecuencia ingest, GDPR consent verified.>

### 3.2 Validation gate (`@data-validator` BLOQUEANTE)

- Temporal leakage check (train cutoff < val cutoff < test cutoff)
- Duplicates cross-split
- Drift baseline computation
- Missing patterns (MNAR detection)
- Subgroup coverage minimum

### 3.3 Feature engineering

<TODO: lista features. Para cada uno: derivacion, types, missing strategy, scaling.>

| Feature | Type | Source | Transformation |
|---|---|---|---|
| `<feat_1>` | numeric | <TODO> | <TODO: log, standardize, ...> |
| `<feat_2>` | categorical | <TODO> | <TODO: target encoding, one-hot, ...> |

## 4. Model architecture

| Concern | Choice | Justification |
|---|---|---|
| Family | <TODO: XGBoost | LightGBM | sklearn LinearModel | PyTorch Transformer | ...> | <TODO: ADR-NNN refs> |
| Hyperparameters | <TODO: lista o ranges Optuna> | <TODO: razon> |
| Loss | <TODO: focal, BCEWithLogits, RMSE, ...> | <TODO> |
| Optimizer | <TODO: AdamW, ...> | <TODO> |
| Regularization | <TODO: L1/L2, dropout, early stopping> | <TODO> |
| Calibration | <TODO: Platt, isotonic, none> | <TODO> |

## 5. Training infrastructure

- Hardware: <TODO: ⟦ gpu ⟧ on-prem | SageMaker ml.g5.2xlarge>
- Tracking: MLflow (single source of truth, ADR-XXX)
- DVC: dataset versions
- Distributed: <TODO: single-GPU | DDP | FSDP via @distributed-training-engineer>
- Reproducibility: seeds + container hash

## 6. Trade-offs

<TODO: opciones evaluadas en C4. Linkear ADR.>

| Decision | Chosen | Alternatives rejected | Reason |
|---|---|---|---|
| <TODO: XGBoost vs DL> | <TODO> | <TODO> | <TODO> |
| <TODO: end-to-end vs feature engineering> | <TODO> | <TODO> | <TODO> |

Detalle: [ADR-NNN](../../adr/NNN-{{SLUG}}.md).

## 7. Failure modes + mitigation

| Failure | Detection | Mitigation |
|---|---|---|
| Training diverge | Loss NaN check | Early abort + alert |
| GPU OOM | torch.cuda.OutOfMemoryError | Reduce batch_size, gradient accumulation |
| Drift detected post-deploy | Prometheus alert | Trigger retraining via MLOps |
| Fairness regression | Subgroup metric drop | Block promote to prod, investigate |
| Concept drift (silent) | Accuracy degradation con ground truth lag | Champion/challenger evaluation, rollback if challenger loses |

## 8. Evaluation protocol

### 8.1 Metrics (`@model-evaluator` + `@math-critic` validation)

- Primary: <TODO: F1 macro / RMSE / NDCG / ...>
- Secondary: <TODO: precision/recall, AUC, Brier, ECE, ...>
- Subgroup metrics: per protected attr breakdown
- Statistical significance: bootstrap CI 95%, n=1000 resamples

### 8.2 Cross-validation

- K-fold stratified k=5 (sin temporal leakage)
- Temporal split si forecasting: TimeSeriesSplit con gap

### 8.3 Baseline comparison

- Naive baseline (majority class / mean / persistence)
- Strong baseline (XGBoost default si DL, LinearModel si tree-based)
- Improvement target: ≥ 5% relative sobre strong baseline

### 8.4 Explainability

- SHAP global (TreeExplainer / DeepExplainer / KernelExplainer)
- SHAP local para predicciones individuales (high-stakes)
- LIME complementario si SHAP no aplicable

## 9. Observability spec

### 9.1 Drift detection (provisioned via Grafana MCP por @monitoring)

- Data drift per feature: KS test (numeric), Chi² (categorical) — Prometheus gauges
- Prediction drift: KL-divergence vs reference window
- Concept drift: accuracy / RMSE en sliding 7-day window
- Threshold defaults: KS > 0.1, Chi² p-value < 0.01, KL > 0.5 → alert

### 9.2 Fairness runtime monitoring

- Per-subgroup metrics emitted as Prometheus gauges
- Demographic parity gap, equal opportunity gap
- Alert if gap > threshold sustained 24h

### 9.3 Cost monitoring

- Per-prediction cost (compute + storage + monitoring overhead)
- Cost anomaly detection (3-sigma sobre rolling window)

### 9.4 Dashboard

Grafana MCP provisioned. Path: `grafana/dashboards/ml_{{SLUG}}.json`. Panels:

1. Predictions volume + latency
2. Drift heatmap (features x time)
3. Fairness per-subgroup
4. Concept drift (accuracy sliding window)
5. Cost per prediction trend
6. Champion vs challenger comparison (si retraining activo)

## 10. Compliance posture

| Regulation | Article | Applicable | Evidence |
|---|---|---|---|
| GDPR | Art 22 | <TODO> | Opt-out endpoint si si |
| GDPR | Art 35 (DPIA) | <TODO> | DPIA documented si high-risk |
| EU AI Act | Art 11 (technical doc) | <TODO> | Model card + ADR + lineage |
| EU AI Act | Art 14 (human oversight) | <TODO> | HITL gate en predictions high-stakes |
| EU AI Act | Art 17 (post-market monitoring) | yes | Drift + fairness dashboards |
| SOC 2 | CC8.1 | yes | Git + MLflow + DVC trail |

## 11. Rollback plan

1. MLflow Registry: transition `Production` → `Archived`, promote previous version to `Production`
2. Serving endpoint: variant routing canary 0% to new, 100% to previous (Argo Rollouts)
3. Feature Store: ensure schema compat (no breaking change)
4. RTO target: <TODO: NN min>

## 12. Open questions

- <TODO: e.g. cuanto vale la mejora del 2% en F1 si hay 10x cost compute?>
