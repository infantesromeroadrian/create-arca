---
description: Inicia pipeline ML completo (14 ciclos C1 Discovery → C14 Sunset). Uso: /ml-new <objetivo>
---
Inicia el pipeline ML completo para: $ARGUMENTS

Pipeline 14 ciclos (v4.0) — cada ciclo requiere artefacto escrito Y aprobación de ⟦ user_name ⟧ antes de avanzar. Detalles canónicos en `rules/pipeline-ml.md` y ADR-016.

## C1 — DISCOVERY
1. @token-optimizer → comprime contexto inicial (≤670 tokens)
2. @skill-router → selecciona skills (requirements-engineering, ml-fundamentals)
3. @project-planner (BLOQUEANTE) → fase A: requisitos 4 niveles (Business/User/System/ML) + ML Problem Statement (tipo, métrica primaria con target, SLA, volumen, fairness); fase B: backlog Jira/Scrum + Scrum Master File; fase C: diagrama Excalidraw context
4. @git-master → crea repo, src-layout, pre-commit hooks, CI/CD inicial
5. ✓ ⟦ user_name ⟧ aprueba requisitos + plan + ML Problem Statement + diagrama → avanzar

## C2 — DATA
1. @data-engineer → ETL pipelines, schemas, Great Expectations, GDPR check
2. @data-validator (BLOQUEANTE) → schema, leakage temporal, duplicados cross-split, drift train/val/test, cobertura por subgrupo
3. @data-scientist → EDA solo sobre train, distribuciones, correlaciones, SHAP baseline
4. @gpu-engineer → si dataset >1M rows, cuDF/RAPIDS
5. @code-critic → gate: idempotencia ETL, leakage, nulls
6. ✓ EDA + dataset audit aprobado → avanzar

## C3 — FEATURE & HYPOTHESIS
1. @data-scientist → feature engineering, hipótesis con tests estadísticos
2. @ml-engineer → feasibility check + spec → @math-critic
3. @alignment-researcher → si LLM: refusal calibration baseline, sycophancy
4. @code-critic → gate: features sin leakage, tests estadísticos válidos
5. ✓ Feature spec + decisión feasibility → avanzar

## C4 — DESIGN
1. @architect-ai (BLOQUEANTE) → ADRs con 2-3 opciones scored, **N diagramas Excalidraw C4 Container** (uno por opción), trade-offs explícitos
2. @ai-engineer → LLM/agentes → @math-critic
3. @prompt-engineer → si LLM: diseño y versionado de prompts
4. @api-designer → OpenAPI, versionado, backwards compat
5. @rag-engineer → si RAG: chunking, embeddings (consultar `docs/roadmap/rag-swarm-inspirations.md`)
6. @agent-engineer → si agentes: ReAct/ReWOO/Reflexion
7. @aws-engineer → si cloud: SageMaker/Bedrock decision
8. @code-critic → gate: consistencia ADRs, interfaces
9. ✓ ADRs firmados + N diagramas C4 → avanzar

## C5 — POC
1. @ml-engineer / @dl-engineer / @ai-engineer → prototype end-to-end → @math-critic
2. @interpretability-researcher → si LLM: refusal direction, attribution baseline
3. @model-evaluator → eval vs baseline declarado en C1
4. @code-critic → gate: prototype reproducible, baseline beat verificable
5. ✓ POC supera baseline → avanzar

## C6 — BUILD
1. @ml-engineer → training pipeline → @math-critic → @debt-detector
2. @dl-engineer → arquitectura DL single-GPU → @math-critic → @debt-detector
3. @distributed-training-engineer → si modelo >8B o multi-node: 3D parallelism, FSDP/DeepSpeed/Megatron, FlashAttention-2/3, FP8
4. @data-engineer + @gpu-engineer → data loading optimizado → @debt-detector
5. @ml-engineer → diagrama Excalidraw training pipeline
6. @code-critic → gate: training loop, reproducibilidad, seeds
7. ✓ Experimento MLflow reproducible + diagrama → avanzar

## C7 — MLOPS
1. @mlops-engineer → MLflow tracking, model registry, DVC si datos >1GB, Feature Store si aplica
2. @aws-engineer → si AWS: SageMaker Model Registry + Pipelines
3. @devops → CI/CD ML gates (coverage + baseline + drift)
4. @code-critic → gate: experimentos versionados, retraining triggers
5. ✓ Modelo registrado + CI/CD ML → avanzar

## C8 — QUALITY
1. @python-specialist → calidad Python → @debt-detector
2. @model-evaluator → métricas + fairness + error analysis → @math-critic
3. @evals-engineer → capability + dangerous capability evals (HELM, MMLU-Pro, GPQA, SWE-bench Verified, METR Autonomy/Apollo deception/WMDP si frontier)
4. @interpretability-researcher → si LLM: SAE features, activation patching
5. @perf-engineer → latencia SLA, quantización, profiling (⟦ gpu ⟧)
6. @tester (BLOQUEANTE) → coverage ≥80%, tests pasando → @debt-detector
7. @maintainability-engineer (paralelo a @code-critic) → longevidad
8. @ai-red-teamer → adversarial testing inicial
9. @code-critic → gate: tests reales, coverage verificada, métricas en subgrupos
10. ✓ Supera baseline + coverage ≥80% + sign-off model-evaluator + maintainability → avanzar

## C9 — PRE-PROD
1. @deployment → staging + load test
2. @devops → chaos engineering, integration tests
3. @cost-analyzer → estimación coste operativo + umbrales alerta
4. @code-critic → gate: SLA bajo carga, integration OK
5. ✓ Staging valida SLA → avanzar

## C10 — DEPLOY
1. @docs-writer → docs freeze: API + runbooks + deployment guide
2. @ai-red-teamer → pentest exhaustivo, prompt injection, ML-specific attacks
3. @trust-and-safety-engineer → si público: jailbreak detection, content moderation, C2PA/SynthID per EU AI Act Art 50
4. @chief-architect (BLOQUEANTE) → audit topology con semáforo per dimension + rollback path en rojo + compliance + trazabilidad C1 → C4 winning option → C10
5. @deployment → diagrama Excalidraw canary rollout
6. @git-master → tag de release, branching
7. @aws-engineer / @devops / @deployment → según target infra
8. @code-critic → gate: Dockerfile, health checks, secrets, rollback ejecutable <5min
9. ✓ Pentest + chief-architect + canary plan → avanzar

## C11 — POST-DEPLOY
1. @deployment → smoke tests prod
2. @monitoring → progressive rollout 1% → 5% → 25% → 100%
3. @model-evaluator → A/B testing vs baseline
4. ✓ Métricas prod ≥ staging → avanzar

## C12 — MONITORING
1. @monitoring → diagrama Excalidraw dashboard (SLO + alerting + drift), data drift + model drift
2. @trust-and-safety-engineer → abuse detection, jailbreak telemetry
3. @frontend-ai → dashboard operativo
4. @code-critic → gate: alertas probadas, thresholds justificados, runbooks ejecutables
5. ✓ Alertas + dashboards validados + drift baseline → avanzar

## C13 — GOVERNANCE & LOOP
1. @evals-engineer → eval continua + RSP/Preparedness/FSF check si frontier
2. @alignment-researcher → refusal calibration drift, sycophancy regression
3. @trust-and-safety-engineer → incident response runbook + DSA Art 17 si aplica
4. @mlops-engineer → retraining triggers + audit trail + compliance log
5. ✓ Governance loop activo → ciclo cierra (sistema vivo)

## C14 — SUNSET (cuando aplique)
1. @architect-ai → retirement plan, archivado, supersession ADR
2. @docs-writer → post-mortem
3. @git-master → tag final, freeze branch
4. ✓ Sistema retirado limpiamente → cierre definitivo

## Reglas de bloqueo (globales)
- NUNCA avanzar sin artefacto escrito que certifique el ciclo
- Ciclo fallido → devolver al especialista con feedback específico
- Deuda técnica detectada = bloqueo hasta resolución
- @math-critic es bloqueante para código de @ml-engineer, @dl-engineer y @ai-engineer en C3/C5/C6/C8
- @code-critic es bloqueante entre ciclos
- 4 gates bloqueantes con dueño nombrado: project-planner C1, data-validator C2, architect-ai C4, chief-architect C10
- Diagramas Excalidraw obligatorios en C1, C4 (N diagramas), C6, C10 (audit + canary), C12

## Soporte transversal (bajo demanda, no bloqueante)
- @sensei → pedagogía
- @token-optimizer → comprimir ≤670 tokens antes de cada delegación
- @code-narrator → auto-invocado tras cada agente que produce código

## Obsidian (al cerrar cada ciclo)
/Projects/<nombre>/CICLO-<N>/{Status,Decisions,Blockers,Retrospective}.md

Formato de invocación por ciclo: [CICLO ACTUAL] → [AGENTE DESTINO] → [CRITERIO DE ÉXITO]
