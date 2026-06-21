---
feature: {{FEATURE}}
slug: {{SLUG}}
type: {{TYPE}}
created: {{DATE}}
status: Draft
related_adr: <TODO: ADR-NNN>
---

# Tasks — {{FEATURE}}

> Sequenced task list mapeado a ARCA Pipeline v4.0 (14 ciclos / 47 fases). Cada task tiene owner agent, effort estimate, gate verification y Definition of Done. Las tareas se ejecutan en orden salvo que la columna `Depends on` indique paralelizacion.

## Cycle mapping summary

| ARCA Cycle | Tasks |
|---|---|
| C1 Discovery | T-001 |
| C4 Design | T-002, T-003 |
| C6 Build | T-004, T-005, T-006, T-007 |
| C8 Quality | T-008, T-009, T-010 |
| C9 Pre-prod | T-011 |
| C10 Deploy | T-012 |
| C11 Post-deploy | T-013 |
| C12 Monitoring | T-014 |

## Tasks

### T-001 — Requirements firmados

- **Cycle:** C1 Discovery
- **Owner:** `@project-planner`
- **Effort:** 2h
- **Depends on:** none
- **Description:** Completar todos los TODOs de `requirements.md`. Validar que stakeholders, user stories y acceptance criteria son medibles y binarios.
- **DoD:**
  - [ ] frontmatter `status: Draft` → `Active`
  - [ ] Cero `<TODO:` strings en `requirements.md`
  - [ ] `triggers_fired` actualizado en `spec.lock.json`
- **Gate:** `@project-planner` sign-off + ⟦ user_name ⟧ aprobacion explicita.

### T-002 — Design firmado + ADR linkeado

- **Cycle:** C4 Design
- **Owner:** `@architect-ai` + `@api-designer`
- **Effort:** 4h
- **Depends on:** T-001
- **Description:** Completar todos los TODOs de `design.md`. Linkear ADR-NNN. Producir Excalidraw `docs/architecture/{{SLUG}}.excalidraw` (C4 Container). Validar que NO hay duplicacion ADR ↔ design.md (linter S4 future).
- **DoD:**
  - [ ] frontmatter `status: Draft` → `Active`
  - [ ] `related_adr` rellenado con ADR-NNN existente
  - [ ] Excalidraw existe + 2-3 opciones evaluadas
  - [ ] OpenAPI 3.1 spec stub creado
- **Gate:** `@architect-ai` sign-off + `@api-designer` review del contract section.

### T-003 — OpenAPI 3.1 contract publicado

- **Cycle:** C4 Design
- **Owner:** `@api-designer`
- **Effort:** 3h
- **Depends on:** T-002
- **Description:** Producir `paths/api/{{SLUG}}.yaml` completo con todos los endpoints, schemas, error responses (RFC 9457 Problem Details), auth scopes, rate limit headers (RFC 6585). Spectral lint pass. Pact contract test stub.
- **DoD:**
  - [ ] Spectral linting passes (zero errors, zero warnings que cuenten)
  - [ ] OpenAPI spec validates con `openapi-spec-validator`
  - [ ] Pact contract test file existe en `tests/contracts/`
  - [ ] `spec.lock.json.files["design.md"]` rehashed (S4 future)
- **Gate:** `@api-designer` sign-off + `@code-critic` review.

### T-004 — Service layer implementado

- **Cycle:** C6 Build
- **Owner:** `@python-specialist` + `@code-critic`
- **Effort:** 6h
- **Depends on:** T-003
- **Description:** Implementar business logic en `services/<service>.py` siguiendo design.md seccion 4 Data flow. Type hints estrictos. Custom exceptions del dominio (no `raise Exception`). Logging estructurado con PII redaction.
- **DoD:**
  - [ ] Service module + tests unitarios
  - [ ] Type hints validados con mypy strict
  - [ ] Custom exceptions definidas en `services/exceptions.py`
  - [ ] Cero violaciones AI slop catalog (19 senales)
- **Gate:** `@code-critic` sign-off (gate bloqueante CLAUDE.md).

### T-005 — Repository / data access

- **Cycle:** C6 Build
- **Owner:** `@python-specialist` + `@data-engineer` (si DB nueva)
- **Effort:** 4h
- **Depends on:** T-003
- **Description:** Implementar repos/ con queries optimizadas. Migrations idempotentes si DB schema cambia. N+1 query check. Connection pool configurado.
- **DoD:**
  - [ ] Repository module + tests con DB real (no mocks — feedback memory: integration tests must hit a real database)
  - [ ] Migrations forward + backward
  - [ ] `EXPLAIN ANALYZE` documented para queries criticas
- **Gate:** `@code-critic` sign-off.

### T-006 — Endpoint handler + middleware

- **Cycle:** C6 Build
- **Owner:** `@python-specialist` + `@deployment`
- **Effort:** 5h
- **Depends on:** T-004, T-005
- **Description:** Implementar endpoint en `api/v1/{{SLUG}}.py`. Middleware: JWT auth, rate limit, idempotency-key, request logging, OpenTelemetry tracing. Error handler RFC 9457 Problem Details.
- **DoD:**
  - [ ] Handler + middleware stack completo
  - [ ] Tests integration con TestClient
  - [ ] OpenTelemetry spans verified (trace_id propagation)
  - [ ] Error responses match Problem Details schema
- **Gate:** `@code-critic` sign-off.

### T-007 — Observability instrumentation

- **Cycle:** C6 Build
- **Owner:** `@monitoring` + `@python-specialist`
- **Effort:** 3h
- **Depends on:** T-006
- **Description:** Emitir metricas Prometheus (RED method), logs JSON con PII redacted, traces OpenTelemetry. Provisionar dashboard Grafana via MCP (`mcp__grafana__update_dashboard`). Definir alert rules.
- **DoD:**
  - [ ] Metricas emitidas + scraped por Prometheus
  - [ ] Dashboard provisionado en Grafana via MCP
  - [ ] Alert rules creadas con runbook links
  - [ ] Logs PII-redacted verificados con `@trust-and-safety-engineer` review
- **Gate:** `@monitoring` sign-off.

### T-008 — Tests coverage ≥ 80%

- **Cycle:** C8 Quality
- **Owner:** `@tester`
- **Effort:** 4h
- **Depends on:** T-006, T-007
- **Description:** Unit + integration + contract tests. Coverage ≥ 80% (CLAUDE.md mandate). Property-based testing para schemas (hypothesis lib). Adversarial inputs (fuzz schema validation).
- **DoD:**
  - [ ] `pytest --cov` ≥ 80%
  - [ ] Pact contract tests passing
  - [ ] Hypothesis property tests en schemas
  - [ ] Adversarial fuzz tests (no panics, errors graceful)
- **Gate:** `@tester` sign-off (gate bloqueante CLAUDE.md).

### T-009 — Security review

- **Cycle:** C8 Quality
- **Owner:** `@ai-red-teamer` (si LLM in scope) o `@code-critic` solo
- **Effort:** 3h
- **Depends on:** T-008
- **Description:** OWASP API Top 10:2023 review. Auth bypass attempts. Input fuzzing. Secret scanning (no hardcoded creds). Dependency CVE check (Trivy/Grype).
- **DoD:**
  - [ ] OWASP matriz design.md §8 verified
  - [ ] Cero secretos hardcoded
  - [ ] Cero CVEs Critical/High en deps
  - [ ] Pen test report (si R2 fired) firmado
- **Gate:** `@code-critic` sign-off + `@ai-red-teamer` si aplica.

### T-010 — Maintainability + outsider-friendly review

- **Cycle:** C8 Quality
- **Owner:** `@maintainability-engineer`
- **Effort:** 2h
- **Depends on:** T-008
- **Description:** Outsider lee design.md + tasks.md y entiende sin rebobinar. Naming sin versionado embebido. Comentarios outsider-friendly (no AI slop). Magic constants nombradas.
- **DoD:**
  - [ ] Outsider test pasado (⟦ user_name ⟧ re-lee tras 1 semana, explica back)
  - [ ] Cero violaciones de los 19 AI slop signals
  - [ ] Constants extraidas a config con nombre
- **Gate:** `@maintainability-engineer` sign-off (gate bloqueante CLAUDE.md C8).

### T-011 — Pre-prod validation

- **Cycle:** C9 Pre-prod
- **Owner:** `@deployment` + `@devops`
- **Effort:** 4h
- **Depends on:** T-009, T-010
- **Description:** Deploy a staging. Load test (k6 / Locust) target del design.md §9. Chaos engineering smoke (kill pod, network partition, DB latency injection).
- **DoD:**
  - [ ] Staging green durante 24h
  - [ ] Load test cumple SLO p95
  - [ ] Chaos test no rompe SLO durante failure injection
- **Gate:** `@deployment` sign-off.

### T-012 — Production deploy con canary

- **Cycle:** C10 Deploy
- **Owner:** `@deployment` + `@chief-architect` (sign-off final)
- **Effort:** 3h
- **Depends on:** T-011
- **Description:** Canary 5% → 25% → 50% → 100% con auto-rollback en degradacion SLO (Argo Rollouts / Flagger). Rollback plan testado y ejecutable en ≤5 min (si R4 fired).
- **DoD:**
  - [ ] Canary completed sin auto-rollback
  - [ ] Rollback plan testado en game day
  - [ ] `@chief-architect` sign-off (gate BLOQUEANTE C10)
- **Gate:** `@chief-architect` sign-off (BLOQUEANTE).

### T-013 — Post-deploy smoke + verification

- **Cycle:** C11 Post-deploy
- **Owner:** `@deployment` + `@monitoring`
- **Effort:** 1h
- **Depends on:** T-012
- **Description:** Smoke test prod con golden path + edge cases. Verificar dashboards muestran trafico real. Alert rules no disparan falsos positivos en primeras 2h.
- **DoD:**
  - [ ] Smoke test passing
  - [ ] Dashboards muestran trafico
  - [ ] Cero alerts spurious en 2h post-deploy
- **Gate:** `@deployment` sign-off.

### T-014 — Monitoring setup + runbook publicado

- **Cycle:** C12 Monitoring
- **Owner:** `@monitoring`
- **Effort:** 2h
- **Depends on:** T-013
- **Description:** SLO documentado, error budget tracking activo, runbook publicado en `runbooks/{{SLUG}}.md`. Drift hook spec-drift-detector.sh verifica spec.lock.json en cron weekly.
- **DoD:**
  - [ ] SLO target documented + tracked
  - [ ] Runbook con on-call escalation paths
  - [ ] Drift hook activo + advisory mode (S4 deliverable)
- **Gate:** `@monitoring` sign-off.

## Total effort estimate

<TODO: sum effort columns. Sample sum: 2+4+3+6+4+5+3+4+3+2+4+3+1+2 = 46h>

## Risks during execution

| Risk | Likelihood | Mitigation |
|---|---|---|
| <TODO: e.g. DB schema conflict con feature paralelo> | <L/M/H> | <TODO> |
| <TODO: e.g. `@code-critic` rejecta T-004 dos veces> | <L/M/H> | Escalar a `@architect-ai` (CLAUDE.md max 2 cycles) |
| <TODO: e.g. canary degrada SLO en T-012> | <L/M/H> | Auto-rollback + retro |

## Status tracking

Estado de cada task se persiste en Obsidian `Projects/<project>/Status.md` y/o issue tracker. Esta tabla NO se mantiene aqui (anti-pattern: status drift entre archivo y realidad).

Re-hash `spec.lock.json` cuando alguna task complete (S4 deliverable).
