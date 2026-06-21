---
name: ml-new
description: Inicia pipeline ML completo de 14 ciclos (C1 Discovery → C14 Sunset). Invócame cuando ⟦ user_name ⟧ diga quiero arrancar un proyecto ML, nuevo modelo, nuevo pipeline, /ml-new, o similar.
when_to_use: arranque de proyecto ML/DL/AI desde cero con pipeline ARCA completo
argument-hint: [objetivo-del-proyecto]
disable-model-invocation: false
user-invocable: true
allowed-tools: Read Grep Glob Bash(git init *) Bash(git status) Bash(ls *) Bash(mkdir *) Write Edit
model: opus
effort: high
---

# /ml-new — pipeline ML 14 ciclos (v4.0)

⟦ user_name ⟧ pidió arrancar un proyecto ML para: `$ARGUMENTS`

Cada ciclo requiere artefacto escrito Y aprobación de ⟦ user_name ⟧ antes de avanzar. NUNCA avanzar sin aprobación explícita. Detalles canónicos en `rules/pipeline-ml.md` y ADR-016.

## Guardas de scope (preflight)

1. Si `$ARGUMENTS` está vacío → pide objetivo a ⟦ user_name ⟧ antes de iniciar.
2. Verifica que el directorio actual es apto (git-ready o inicializable).
3. Si hay `data/` grande (>1GB) o GPU required, avisa upfront.

## C1 — DISCOVERY

1. @token-optimizer — comprime contexto inicial (≤670 tokens)
2. @skill-router — selecciona skills (requirements-engineering, ml-fundamentals)
3. @project-planner (BLOQUEANTE) — fase A: elicita requisitos 4 niveles (Business/User/System/ML) + ML Problem Statement (tipo de tarea, métrica primaria con target, SLA latencia, volumen, fairness); fase B: backlog Jira/Scrum + Scrum Master File con hitos; fase C: diagrama Excalidraw context (stakeholders + componentes derivados de requisitos)
4. @git-master — crea repo, estructura src-layout, pre-commit hooks, CI/CD inicial
5. ✓ ⟦ user_name ⟧ aprueba doc de requisitos + plan + ML Problem Statement + diagrama Excalidraw → avanzar

## C2 — DATA

1. @data-engineer — pipelines ETL, schemas explícitos, Great Expectations, GDPR check
2. @data-validator (BLOQUEANTE) — schema, leakage temporal, duplicados cross-split, drift train/val/test, cobertura por subgrupo
3. @data-scientist — EDA solo sobre train (nunca test), distribuciones, correlaciones, SHAP baseline
4. @gpu-engineer — si dataset >1M rows, optimización cuDF/RAPIDS
5. @code-critic — gate: idempotencia ETL, leakage, nulls manejados
6. ✓ EDA + dataset audit aprobado por @data-validator → avanzar

## C3 — FEATURE & HYPOTHESIS

1. @data-scientist — feature engineering, hipótesis con tests estadísticos
2. @ml-engineer — feasibility check + spec → @math-critic (gate matemático)
3. @alignment-researcher — si LLM: refusal calibration baseline, sycophancy assessment
4. @code-critic — gate: features sin leakage, transformaciones reversibles, tests estadísticos válidos
5. ✓ Feature spec + decisión feasibility documentada → avanzar

## C4 — DESIGN

1. @architect-ai (BLOQUEANTE) — literature review, ADRs detallados con 2-3 opciones scored, **N diagramas Excalidraw C4 Container (uno POR opción, no solo la ganadora)**, trade-offs explícitos
2. @ai-engineer — diseño LLM/agentes si aplica → @math-critic
3. @prompt-engineer — si LLM/agentes: diseño y versionado de prompts del sistema
4. @api-designer — OpenAPI, versionado, backwards compat
5. @rag-engineer — si RAG: chunking, embeddings, retrieval strategy (consultar `docs/roadmap/rag-swarm-inspirations.md` antes)
6. @agent-engineer — si agentes: patrones ReAct/ReWOO, límites
7. @aws-engineer — si cloud: SageMaker/Bedrock decision
8. @code-critic — gate: consistencia ADRs, interfaces, asunciones
9. ✓ ADRs firmados + N diagramas C4 → avanzar

## C5 — POC

1. @ml-engineer / @dl-engineer / @ai-engineer — prototype minimal end-to-end → @math-critic
2. @interpretability-researcher — si LLM: análisis preliminar de circuitos relevantes (refusal direction, attribution baseline)
3. @model-evaluator — evaluación vs baseline declarado en C1
4. @code-critic — gate: prototype reproducible, baseline beat verificable
5. ✓ POC end-to-end supera baseline → avanzar

## C6 — BUILD

1. @ml-engineer — training pipeline → @math-critic → @debt-detector
2. @dl-engineer — arquitectura DL single-GPU → @math-critic → @debt-detector
3. @distributed-training-engineer — si modelo >8B params o multi-node: 3D parallelism (TP×PP×DP), FSDP/DeepSpeed/Megatron, FlashAttention-2/3, FP8 H100/B200
4. @data-engineer + @gpu-engineer — data loading optimizado → @debt-detector
5. @ml-engineer — diagrama Excalidraw training pipeline (dataset → preprocessing → model → eval → registry)
6. @code-critic — gate: training loop, reproducibilidad, seeds, leakage train/test
7. ✓ Experimento MLflow reproducible + diagrama training → avanzar

## C7 — MLOPS

1. @mlops-engineer — MLflow tracking, model registry, DVC versioning si datos >1GB, Feature Store si aplica
2. @aws-engineer — si AWS: SageMaker Model Registry + Pipelines
3. @devops — CI/CD gates para ML (coverage + baseline + drift)
4. @code-critic — gate: experimentos versionados, retraining triggers definidos
5. ✓ Modelo registrado + CI/CD ML configurado → avanzar

## C8 — QUALITY

1. @python-specialist — revisión calidad Python → @debt-detector
2. @model-evaluator — métricas + fairness + error analysis → @math-critic
3. @evals-engineer — capability + dangerous capability evals (HELM, MMLU-Pro, GPQA, SWE-bench Verified si aplica; METR Autonomy/Apollo deception/WMDP si frontier)
4. @interpretability-researcher — si LLM: SAE features, activation patching de comportamientos críticos
5. @perf-engineer — latencia SLA, quantización, profiling (calibrado ⟦ gpu ⟧)
6. @tester (BLOQUEANTE) — suite completa, falla si coverage <80% o tests rojos → @debt-detector
7. @maintainability-engineer (paralelo a @code-critic) — longevidad: cohesion, coupling, naming, abstracciones
8. @ai-red-teamer — adversarial testing inicial
9. @code-critic — gate: tests reales, coverage verificada, métricas en subgrupos
10. ✓ Supera baseline + coverage ≥80% + sign-off de model-evaluator + maintainability → avanzar

## C9 — PRE-PROD

1. @deployment — staging environment + load test
2. @devops — chaos engineering, integration tests
3. @cost-analyzer — estimación coste operativo (inferencia, storage, tokens) + umbrales de alerta
4. @code-critic — gate: SLA cumple bajo carga, integración OK
5. ✓ Staging valida SLA + integration tests verdes → avanzar

## C10 — DEPLOY

1. @docs-writer — docs freeze: API docs + runbooks + deployment guide
2. @ai-red-teamer — pentest exhaustivo, prompt injection, ML-specific attacks
3. @trust-and-safety-engineer — si producto público: jailbreak detection runtime, content moderation pipeline (PhotoDNA si imágenes), C2PA/SynthID si genera contenido per EU AI Act Art 50
4. @chief-architect (BLOQUEANTE) — audit topology con semáforo per dimension + rollback path flechado en rojo + compliance annotations + trazabilidad C1 → C4 winning option → C10
5. @deployment — diagrama Excalidraw canary rollout topology
6. @git-master — tag de release, branching
7. @aws-engineer / @devops / @deployment — según target infra
8. @code-critic — gate: Dockerfile, health checks, secrets, rollback plan ejecutable <5min
9. ✓ Pentest sign-off + chief-architect aprobado + canary plan → avanzar

## C11 — POST-DEPLOY

1. @deployment — smoke tests en prod
2. @monitoring — progressive rollout 1% → 5% → 25% → 100%
3. @model-evaluator — A/B testing vs baseline en producción
4. ✓ Métricas en prod ≥ staging → avanzar

## C12 — MONITORING

1. @monitoring — diagrama Excalidraw dashboard (SLO + alerting + drift detection paths), data drift + model drift + alertas con thresholds calibrados
2. @trust-and-safety-engineer — abuse detection production, jailbreak telemetry
3. @frontend-ai — dashboard operativo (Next.js + recharts/plotly)
4. @code-critic — gate: alertas probadas, thresholds justificados, runbooks ejecutables
5. ✓ Alertas probadas + dashboards validados + drift baseline → avanzar

## C13 — GOVERNANCE & LOOP

1. @evals-engineer — eval continua (capability regression + RSP/Preparedness/FSF check si aplica)
2. @alignment-researcher — refusal calibration drift, sycophancy regression
3. @trust-and-safety-engineer — incident response runbook + DSA Art 17 appeals si aplica
4. @mlops-engineer — retraining triggers + audit trail + compliance log
5. ✓ Governance loop activo → ciclo cierra (sistema vivo)

## C14 — SUNSET (cuando aplique)

1. @architect-ai — retirement plan, archivado de artefactos, supersession ADR
2. @docs-writer — post-mortem
3. @git-master — tag final, freeze branch
4. ✓ Sistema retirado limpiamente → cierre definitivo

## Reglas de bloqueo (globales)

- NUNCA avanzar sin artefacto escrito que certifique el ciclo
- Ciclo fallido → devolver al especialista con feedback específico
- Deuda técnica detectada = bloqueo hasta resolución
- @math-critic es bloqueante para código de @ml-engineer, @dl-engineer, @ai-engineer en C3/C5/C6/C8
- @code-critic es bloqueante entre ciclos
- @data-validator es bloqueante en C2 antes de cerrar EDA
- @architect-ai es bloqueante en C4 antes de firmar ADR
- @chief-architect es bloqueante en C10 antes de deploy
- @tester es bloqueante en C8 antes de avanzar a C9
- Diagramas Excalidraw obligatorios en C1, C4 (N diagramas), C6, C10 (audit + canary), C12

## Soporte transversal (bajo demanda, no bloqueante)

- @sensei — pedagogía. Invocar cuando ⟦ user_name ⟧ pide "explícame", "por qué", o está aprendiendo un concepto nuevo durante cualquier ciclo.
- @token-optimizer — comprimir contexto ≤670 tokens antes de cada delegación y ≤200 tokens antes de guardar en Engram.
- @code-narrator — auto-invocado tras cada agente que produce código (pedagógico, no bloqueante).

## Obsidian (al cerrar cada ciclo)

`/Projects/<nombre>/CICLO-<N>/{Status,Decisions,Blockers,Retrospective}.md`

## Formato de respuesta por ciclo

`[CICLO ACTUAL] → [AGENTE DESTINO] → [CRITERIO DE ÉXITO]`

**ultrathink** antes de cerrar cada ciclo para validar que el artefacto realmente cumple el criterio — no solo que existe.
