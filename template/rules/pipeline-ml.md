---
paths:
  - "**/ml/**"
  - "**/models/**"
  - "**/*train*.py"
  - "**/notebooks/**"
  - "**/*.ipynb"
  - "**/pipelines/**"
  - "**/mlruns/**"
  - "**/dvc.yaml"
---

# ARCA Pipeline v4.0 — 14 Ciclos / 65 Fases

Pipeline completo para proyectos ML/DL/AI/Agentic/GenAI. Se carga automáticamente al tocar archivos en paths ML. Activación manual: `/ml-new`, `/rag-new`, `/ml-agent`, `/ml-dl`.

**Principios duros**:
- Ninguna fase avanza sin artefacto escrito que la certifique.
- Ningún ciclo avanza sin gate bloqueante aprobado.
- Fase fallida → vuelve al agente propietario con feedback específico (máx 2 ciclos de rechazo → escalar a `@architect-ai`).
- Manager estricto: el 99% no está bien. `@code-critic`, `@math-critic` y `@debt-detector` auditan antes de cerrar.

---

## CICLO 1 · DISCOVERY

| ID | Fase | Agente propietario |
|---|---|---|
| **F0.0** | Problem Discovery — ¿merece resolverse con ML? | `@project-planner` |
| **F0.1** | Business Understanding (CRISP-DM 1) | `@project-planner` |
| **F0.3** | Requirements 4 niveles (Business/User/System/ML) | `@project-planner` + `@git-master` |
| **F0.5** | Planning / Sprint 0 + Scrum Master File | `@project-planner` + `@architect-ai` |
| **F0.7** | Ecosystem Assessment (laboral vs propio, infra disponible) | `@architect-ai` + `@aws-engineer` |

**🚪 GATE C1 (bloqueante para avanzar a C2)**:
Sign-off ⟦ user_name ⟧ + artefacto escrito de requisitos + plan de sprint aprobado + infra identificada.

---

## CICLO 2 · DATA

| ID | Fase | Agente propietario |
|---|---|---|
| **F1.0** | Data Sourcing / Acquisition | `@data-engineer` |
| **F1.2** | Data Legal / GDPR / PII Audit | `@ai-red-teamer` + `@data-engineer` |
| **F1.4** | Data Ingestion / ETL | `@data-engineer` |
| **F1.6** | Data Pipeline (raw → clean → modeled → consumed) | `@data-engineer` |
| **F1.8** | EDA Statistical | `@data-scientist` |
| **F1.9** | **Data Validation BLOQUEANTE** (leakage, duplicates, drift, MNAR, cobertura) | `@data-validator` |

**🚪 GATE C2 (bloqueante para avanzar a C3)**:
`@data-validator` APROBADO + `@code-critic` sobre pipelines ETL + datos legales verificados.

---

## CICLO 3 · FEATURE & HYPOTHESIS

| ID | Fase | Agente propietario |
|---|---|---|
| **F2.0** | Hypothesis Testing / Business EDA | `@data-scientist` |
| **F2.2** | Feature Engineering | `@data-scientist` + `@ml-engineer` + `@math-critic` |
| **F2.4** | Feature Store Setup (Feast) | `@mlops-engineer` |
| **F2.6** | Spec Definition (tarea, métricas primarias, baseline, SLA, fairness) | ARCA + `@project-planner` valida |
| **F2.8** | Feasibility / Preliminary Baseline | `@architect-ai` + `@model-evaluator` |
| **F2.x** | Post-producer pedagogical narration (auto-invoked) | `@code-narrator` |

**🚪 GATE C3 (bloqueante para avanzar a C4)**:
Spec firmada por ⟦ user_name ⟧ + feasibility probada en datos reales + `@math-critic` sobre features + `@code-critic` sobre pipelines.

---

## CICLO 4 · DESIGN

| ID | Fase | Agente propietario |
|---|---|---|
| **F3.0** | Literature Review / SOTA | `@architect-ai` |
| **F3.2** | Software Architecture Design | `@architect-ai` |
| **F3.4** | ML/DL/AI Architecture Design | `@ml-engineer` / `@dl-engineer` / `@ai-engineer` / `@agent-engineer` / `@rag-engineer` |
| **F3.6** | API Contract Design (OpenAPI/gRPC) | `@api-designer` |
| **F3.8** | Cloud Architecture Design | `@aws-engineer` + `@devops` |
| **F3.x** | Threat Modeling (adversarial review of architecture) | `@ai-red-teamer` |

**🚪 GATE C4 (bloqueante para avanzar a C5)**:
ADRs firmados (SOLID, trade-offs, alternativas rechazadas) + `@math-critic` sobre architectures ML + `@code-critic` sobre contratos.

---

## CICLO 5 · POC

| ID | Fase | Agente propietario |
|---|---|---|
| **F4.0** | POC / Prototype (minimal end-to-end) | `@ml-engineer` / `@dl-engineer` / `@ai-engineer` / `@agent-engineer` |
| **F4.2** | POC Evaluation (¿supera baseline?) | `@model-evaluator` + `@math-critic` |
| **F4.3** | **Adversarial Smoke-Test BLOQUEANTE** (FGSM/PGD single-step ε=8/255 o HarmBench Tier 1 50-prompt, budget 15min) | `@ai-red-teamer` |
| **F4.x** | Post-producer pedagogical narration (auto-invoked) | `@code-narrator` |

**🚪 GATE C5 (bloqueante para avanzar a C6)**:
POC supera baseline preliminar + `@ai-red-teamer` adversarial smoke-test PASS (no P0/P1 obvio). Si falla baseline → vuelve a C4 (rediseño). Si falla adversarial smoke → vuelve al producer (`@ml-engineer`/`@dl-engineer`/`@ai-engineer`) con finding RT-YYYY-NNNN.md, max 2 ciclos antes de escalar a `@architect-ai` (reconsider model architecture).
`@maintainability-engineer` review ligero (atomicidad + ml-code-store candidates en `<proyecto>/ml-code-store-proposals.md`, ADR-026).

---

## CICLO 6 · BUILD

| ID | Fase | Agente propietario |
|---|---|---|
| **F5.0** | Training Pipeline (código prod-grade) | `@ml-engineer` / `@dl-engineer` |
| **F5.2** | Feature Pipeline Prod-Grade | `@data-engineer` + `@ml-engineer` |
| **F5.4** | Hyperparameter Tuning (Optuna) | `@ml-engineer` / `@dl-engineer` + `@math-critic` |
| **F5.6** | Model Training (full) | `@ml-engineer` / `@dl-engineer` / `@ai-engineer` + `@gpu-engineer` |
| **F5.8** | Model Calibration (Platt / isotonic) | `@ml-engineer` + `@math-critic` |
| **F5.9** | **Adversarial Probe Training-Time BLOQUEANTE** (BadNets activation viz + Carlini poisoning detection + LLM jailbreak smoke 10% suite, budget 30min) | `@ai-red-teamer` |
| **F5.x** | Post-producer pedagogical narration (auto-invoked) | `@code-narrator` |

**🚪 GATE C6 (bloqueante para avanzar a C7)**:
Cadena `@math-critic` → `@debt-detector` → (`@code-critic` ‖ `@maintainability-engineer`) → **`@ai-red-teamer` adversarial probe** sobre todo el código de training + modelo entrenado. `@maintainability-engineer` audita atomicidad + ml-code-store candidates (ADR-026) y bloquea si detecta `STORE-DUPLICATION` o `STORE-EXISTS-NOT-USED`. `@ai-red-teamer` bloquea si detecta backdoor activation patterns, poisoning signatures, o jailbreak success rate >5% en LLM checkpoints — finding RT-YYYY-NNNN.md con remediation owner asignado.

---

## CICLO 7 · MLOPS

| ID | Fase | Agente propietario |
|---|---|---|
| **F6.0** | Experiment Tracking (MLflow) | `@mlops-engineer` |
| **F6.2** | Model Registry (versionado con dataset) | `@mlops-engineer` |
| **F6.4** | Data Versioning (DVC) | `@mlops-engineer` + `@data-engineer` |
| **F6.6** | CI/CD Pipeline Setup | `@devops` + `@git-master` |

**🚪 GATE C7 (bloqueante para avanzar a C8)**:
Experimento reproducible (clonar repo limpio + `pip install` + `python train.py` → funciona). Modelo en Registry con versión + dataset trazable. CI/CD pasa.

---

## CICLO 8 · QUALITY

| ID | Fase | Agente propietario |
|---|---|---|
| **F7.0** | **Code Quality BLOQUEANTE** (tests ≥80% coverage) | `@python-specialist` + `@tester` |
| **F7.2** | Model Evaluation (métricas, CV, IC bootstrap) | `@model-evaluator` + `@math-critic` |
| **F7.4** | LLM/Agent Evaluation (LangSmith, RAGAS) — si aplica | `@ai-engineer` + `@agent-engineer` + `@rag-engineer` |
| **F7.6** | Performance Benchmark (p50/p95/p99 latencia) | `@perf-engineer` |
| **F7.8** | Fairness / Bias Audit | `@model-evaluator` + `@ai-red-teamer` |
| **F7.9** | Security / Adversarial Audit | `@ai-red-teamer` |
| **F7.x** | Post-producer pedagogical narration (auto-invoked) | `@code-narrator` |

**🚪 GATE C8 (bloqueante para avanzar a C9)**:
`@tester` BLOQUEANTE (coverage ≥80% + CV) + `@model-evaluator` baseline superado + `@ai-red-teamer` sin CRITICAL ni HIGH + `@math-critic` métricas válidas (IC, significancia) + `@maintainability-engineer` audit completo de longevidad y verificación de migraciones aprobadas al ml-code-store (ADR-026).

---

## CICLO 9 · PRE-PROD

| ID | Fase | Agente propietario |
|---|---|---|
| **F8.0** | Staging Deploy (IaC idéntico a prod) | `@devops` + `@aws-engineer` + `@deployment` |
| **F8.2** | Load / Stress Test (concurrent users realistas) | `@perf-engineer` + `@devops` |
| **F8.4** | Integration Test End-to-End | `@tester` + `@python-specialist` |
| **F8.6** | Chaos Engineering (opcional — kill pods, latency inject) | `@devops` |
| **F8.x** | Pen-test Staging (adversarial probe of pre-prod surface) | `@ai-red-teamer` |

**🚪 GATE C9 (bloqueante para avanzar a C10)**:
Smoke + integration verdes en staging + load test sin degradación + SLO latencia cumplido bajo carga real.

---

## CICLO 10 · DEPLOY

| ID | Fase | Agente propietario |
|---|---|---|
| **F9.0** | Documentation Freeze (API docs + runbooks) | `@docs-writer` |
| **F9.2** | Security Pentest Final | `@ai-red-teamer` |
| **F9.4** | **Chief-Architect Final Sign-off BLOQUEANTE** | `@chief-architect` |
| **F9.6** | Cloud Deploy / K8s / Serverless | `@aws-engineer` / `@devops` / `@deployment` |
| **F9.8** | Canary / Shadow Deploy (10% → 50% → 100%) | `@deployment` + `@monitoring` |

**🚪 GATE C10 (bloqueante para avanzar a C11)**:
`@chief-architect` APROBADO + rollback ejecutable <5 min + canary sin degradación en cada escalón.

---

## CICLO 11 · POST-DEPLOY

| ID | Fase | Agente propietario |
|---|---|---|
| **F10.0** | Smoke Test en Producción (endpoints responden, métricas sanas) | `@monitoring` + `@deployment` |
| **F10.2** | Progressive Rollout | `@deployment` + `@monitoring` |
| **F10.4** | A/B Testing (vs modelo anterior — si aplica) | `@model-evaluator` + `@data-scientist` |

**🚪 GATE C11 (bloqueante para avanzar a C12)**:
Smoke prod OK + primer request real OK + métricas iniciales dentro de SLO.

---

## CICLO 12 · MONITORING

| ID | Fase | Agente propietario |
|---|---|---|
| **F11.0** | SLO / SLI Monitoring | `@monitoring` |
| **F11.2** | Data Drift Detection (EvidentlyAI) | `@monitoring` + `@mlops-engineer` |
| **F11.4** | Model Drift / Performance Decay | `@monitoring` + `@mlops-engineer` |
| **F11.6** | Security Monitoring (prompt injection, abuse, anomalías) | `@ai-red-teamer` + `@monitoring` |
| **F11.8** | Cost Monitoring | `@cost-analyzer` |

**🚪 GATE C12 (continuo, no bloqueante de avance — activa triggers en C13)**:
Alertas calibradas con datos reales + dashboards validados + drift thresholds documentados.

---

## CICLO 13 · GOVERNANCE & LOOP

| ID | Fase | Agente propietario |
|---|---|---|
| **F12.0** | Model Governance / Audit Trail | `@docs-writer` + `@mlops-engineer` |
| **F12.2** | Compliance Review (auditor externo en proyectos laborales) | `@ai-red-teamer` |
| **F12.4** | Retraining Trigger (threshold drift) | `@mlops-engineer` + `@monitoring` |
| **F12.6** | Incident Response / Rollback | `@deployment` + `@monitoring` |

**🚪 GATE C13 (reactivo — dispara loop a C2/C6 cuando corresponda)**:
- Retraining trigger activado → loop a C2 (nuevos datos) o C6 (rebuild)
- Incident crítico → rollback automático + post-mortem en C14.

---

## CICLO 14 · SUNSET

| ID | Fase | Agente propietario |
|---|---|---|
| **F13.0** | Model Sunset / Retirement | `@chief-architect` + `@mlops-engineer` |
| **F13.2** | Archive Weights + Data | `@mlops-engineer` + `@aws-engineer` |
| **F13.4** | Endpoint Shutdown | `@deployment` + `@devops` |
| **F13.6** | Post-Mortem / Lessons Learned | `@docs-writer` + `@architect-ai` |

**🚪 GATE C14 (cierre formal)**:
Pesos archivados + datos archivados con retention policy + endpoint down sin tráfico residual + post-mortem firmado.

---

## Gates transversales (aplican en todos los ciclos)

| Gate | Trigger | Enforcement |
|---|---|---|
| **Preflight** | Antes de cualquier invocación a especialista | `@token-optimizer` + `@skill-router` obligatorios. Hook `delegation-preflight-enforcer.sh` bloquea si faltan. |
| **Math Critic** | Código de `@ml-engineer` / `@dl-engineer` / `@ai-engineer` | Obligatorio antes de `@code-critic`. Hook `math-critic-gate-enforcer.sh` emite `decision: block` si se salta. |
| **Code Critic** | Invocación de `@chief-architect` o `@deployment` con productor previo | Hook `code-critic-gate-enforcer.sh` bloquea si último productor no pasó por `@code-critic`. |
| **Maintainability** | Código nuevo en C5/C6/C8 (cualquier productor) | `@maintainability-engineer` corre en paralelo a `@code-critic`. Bloquea por `STORE-DUPLICATION` / `STORE-EXISTS-NOT-USED`. Advisory por `STORE-CANDIDATE`. ADR-026. |
| **Sign-off ⟦ user_name ⟧** | Cierre de C1, C3, C4, C10 + cada `STORE-CANDIDATE` aprobado individualmente | Manual. Sin sign-off escrito no avanza. |

## ml-code-store mandate (ADR-026)

Cada proyecto mantiene un directorio `ml-code-store/{ml,data,utils}/<sub>/` con código atómico, reutilizable cross-proyecto y escalable. `@project-planner` crea el skeleton en C1. `@maintainability-engineer` audita en C5/C6/C8 y emite proposals (`<proyecto>/ml-code-store-proposals.md`). ⟦ user_name ⟧ aprueba/rechaza/modifica candidato a candidato (HITL strict). `@python-specialist` ejecuta la migración aprobada. Hook advisory `ml-code-store-duplication-detector.sh` (PostToolUse:Edit/Write) avisa de similitud >80% con código existente del store.

---

## Diagramas obligatorios (via Excalidraw MCP)

| Ciclo | Diagrama | Propietario |
|---|---|---|
| C1 | Context diagram + stakeholders | `@architect-ai` |
| C4 | Architecture C4 (context/container/component) | `@architect-ai` |
| C6 | Training pipeline diagram | `@ml-engineer` / `@dl-engineer` |
| C10 | Deployment topology + rollback flow | `@chief-architect` + `@deployment` |
| C12 | Monitoring dashboard layout | `@monitoring` |

---

## Activación

- `/ml-new <objetivo>` → C1 completo (F0.0 → F0.7)
- `/rag-new <objetivo>` → arranca en C4 (F3.4) asumiendo datos ya auditados
- `/ml-agent <objetivo>` → arranca en C4 (F3.4) para agentes
- `/ml-dl <objetivo>` → arranca en C4 (F3.4) para fine-tuning DL

## Obsidian (al cerrar cada ciclo)

`/Projects/<nombre>/{CICLO-N}/{Status, Decisions, Blockers, Retrospective}.md`
