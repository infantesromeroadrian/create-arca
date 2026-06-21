---
feature: {{FEATURE}}
slug: {{SLUG}}
type: {{TYPE}}
created: {{DATE}}
status: Draft
related_adr: <TODO: ADR-NNN>
related_excalidraw: <TODO: docs/architecture/{{SLUG}}.excalidraw>
---

# Design — {{FEATURE}}

> **Single source of truth rule:** decisiones arquitecturales viven en `docs/adr/NNN-{{SLUG}}.md`. Este archivo NO duplica esa prosa — linkea. Si el contenido se repite, mover al ADR y dejar solo el link aqui.

## 1. Architecture summary

<TODO: 1 parrafo. Que componentes existen, como se comunican, donde vive el contract.>

Reference: [ADR-NNN](../../adr/NNN-{{SLUG}}.md) seccion `Decision`.

Diagrama: [{{SLUG}}.excalidraw](../../architecture/{{SLUG}}.excalidraw)

## 2. Components affected

| Component | Type | Action | Owner agent |
|---|---|---|---|
| `<TODO: e.g. api/v1/{{SLUG}}>` | Endpoint | Create | `@api-designer` + `@deployment` |
| `<TODO: e.g. services/<service>.py>` | Service layer | Modify | `@python-specialist` |
| `<TODO: e.g. repos/<repo>.py>` | Data access | Create | `@python-specialist` |
| `<TODO: e.g. tests/api/test_{{SLUG}}.py>` | Tests | Create | `@tester` |
| `<TODO: e.g. openapi.yaml>` | Contract | Modify | `@api-designer` |
| `<TODO: e.g. grafana/dashboards/{{SLUG}}.json>` | Dashboard | Create | `@monitoring` (via Grafana MCP) |

## 3. API contract

### 3.1 Endpoints

<TODO: tabla de endpoints. Cada uno con METHOD, path, summary, auth, idempotent.>

| Method | Path | Summary | Auth scope | Idempotent |
|---|---|---|---|---|
| `<METHOD>` | `<path>` | `<summary>` | `<scope>` | `<yes/no>` |

### 3.2 Request schema

<TODO: pseudocode JSON Schema 2020-12 o referencia al fichero OpenAPI.>

```yaml
# paths/api/{{SLUG}}.yaml (excerpt)
<TODO: schema definitions>
```

### 3.3 Response schema

<TODO: success + error responses. RFC 9457 Problem Details para errores.>

```yaml
<TODO: response schemas>
```

### 3.4 Error codes

| HTTP | error.code | When |
|---|---|---|
| 400 | `validation_error` | Schema mismatch |
| 401 | `unauthenticated` | No JWT or invalid signature |
| 403 | `forbidden` | JWT valid pero scope insuficiente |
| 404 | `not_found` | Resource ID inexistente |
| 409 | `conflict` | Idempotency key reused con payload distinto |
| 422 | `unprocessable_entity` | Schema valido pero semantica invalida |
| 429 | `rate_limited` | Quota excedida |
| 500 | `internal_error` | Bug en server (ALERT trigger) |

## 4. Data flow

<TODO: secuencia paso a paso. Quien llama a quien, que data fluye, donde se persiste.>

```
1. Client → POST /api/v1/{{SLUG}} con JWT
2. API gateway valida JWT + scope (auth/0)
3. Rate limiter check (Redis bucket por tenant)
4. Handler valida schema (JSON Schema 2020-12)
5. Service layer: <TODO: business logic>
6. Repository: <TODO: persistencia DB / cache / message bus>
7. Response: 2xx con schema + headers RFC 6585 rate limit
```

## 5. Tech stack choices

| Concern | Choice | Justification |
|---|---|---|
| Framework | <TODO: FastAPI | gRPC server | tornado | ...> | <TODO: ADR-NNN refs> |
| Validation | <TODO: pydantic v2 | jsonschema | proto> | <TODO: razon> |
| Auth | <TODO: jose JWT | authlib oauth2.1> | <TODO: razon> |
| DB | <TODO: PostgreSQL 16 | DynamoDB | sqlite>  | <TODO: razon> |
| Cache | <TODO: Redis | Valkey | n/a> | <TODO: razon> |
| Observability | Prometheus + Grafana MCP + OpenTelemetry | ARCA default (ADR-009 hybrid posture) |

## 6. Trade-offs

<TODO: opciones consideradas en C4 + razon de la elegida. Linkear ADR para detalle.>

| Decision | Chosen | Alternatives rejected | Reason |
|---|---|---|---|
| <TODO: e.g. sync vs async response> | <TODO> | <TODO> | <TODO> |
| <TODO: e.g. JWT vs mTLS> | <TODO> | <TODO> | <TODO> |
| <TODO: e.g. soft delete vs hard> | <TODO> | <TODO> | <TODO> |

Detalle completo: [ADR-NNN](../../adr/NNN-{{SLUG}}.md) seccion `Rationale`.

## 7. Failure modes + mitigation

| Failure | Detection | Mitigation |
|---|---|---|
| DB unavailable | Health check + Prometheus alert | Circuit breaker → 503 + retry-after |
| Rate limit exhausted | 429 emitted | Backoff + jitter en cliente |
| JWT JWKS endpoint down | 503 desde authn middleware | Cache JWKS keys 24h con stale-while-revalidate |
| Idempotency key collision | 409 emitted | Cliente resuelve manualmente (no auto-retry) |
| Schema drift entre code y OpenAPI | CI gate | Block PR (S4 spec-drift-detector) |

## 8. Security posture

<TODO: matriz OWASP API Top 10:2023. Linkear a `@ai-red-teamer` review si aplica.>

| OWASP API risk | Mitigation |
|---|---|
| API1:2023 BOLA | <TODO: per-resource ABAC + tenant scoping en query> |
| API2:2023 Broken Authentication | <TODO: JWT JWKS + scope check + refresh token rotation> |
| API3:2023 Broken Object Property Level Authorization | <TODO: response shaping per scope> |
| API4:2023 Unrestricted Resource Consumption | <TODO: rate limit + body size cap + timeout> |
| API5:2023 Broken Function Level Authorization | <TODO: scope:action enum> |
| API6:2023 SSRF | <TODO: URL allowlist en outbound calls, no SSRF posible> |
| API7:2023 Server-Side Request Forgery | <TODO: input URL sanitization> |
| API8:2023 Security Misconfiguration | <TODO: CIS benchmark + cdk-nag> |
| API9:2023 Improper Inventory Management | <TODO: OpenAPI spec versioned + deprecation headers> |
| API10:2023 Unsafe Consumption of APIs | <TODO: schema validation en responses upstream> |

## 9. Performance budget

| Metric | Target | Measurement |
|---|---|---|
| Latency p50 | <TODO: NN ms> | Prometheus histogram |
| Latency p95 | <TODO: NN ms> | Prometheus histogram |
| Latency p99 | <TODO: NN ms> | Prometheus histogram |
| Throughput sustained | <TODO: NN req/s> | Load test (S5 piloto) |
| Cost per request | <TODO: $0.NNNN> | Cost monitoring per-request |

## 10. Observability spec

<TODO: especifica metricas, logs, traces que `@monitoring` debe provisionar.>

### 10.1 Metrics (Prometheus)

```promql
# Latency histogram per endpoint + status code
http_request_duration_seconds_bucket{endpoint="/api/v1/{{SLUG}}", status="2xx"}

# Error rate
rate(http_requests_total{endpoint="/api/v1/{{SLUG}}", status=~"5.."}[5m])

# Saturation (in-flight requests)
http_requests_in_flight{endpoint="/api/v1/{{SLUG}}"}
```

### 10.2 Logs (structured JSON)

```json
{
  "timestamp": "<ISO 8601>",
  "level": "info|warn|error",
  "trace_id": "<W3C>",
  "span_id": "<W3C>",
  "endpoint": "/api/v1/{{SLUG}}",
  "tenant_id": "<id>",
  "user_id": "<redacted hash>",
  "duration_ms": <int>,
  "status": <int>,
  "error_code": "<RFC 9457 type>"
}
```

PII fields excluidos: <TODO: lista campos request/response que NO se loguean>.

### 10.3 Traces (OpenTelemetry)

W3C Trace Context propagation obligatorio. Spans:

- `api.handler` (root)
- `api.auth.jwt_verify`
- `api.ratelimit.check`
- `api.service.<verb>` (business logic)
- `api.repo.<query>` (DB / cache)

### 10.4 Dashboard

Provisioned via Grafana MCP por `@monitoring`. Path: `grafana/dashboards/{{SLUG}}.json`.

Panels:

1. RED method (Rate / Errors / Duration)
2. Error budget burn-rate (multi-window 5m/1h/6h/3d)
3. Saturation (in-flight + queue)
4. Cost per request
5. Auth failures breakdown (401 / 403 / 429)

### 10.5 Alerts

| Alert | Threshold | Severity | Runbook |
|---|---|---|---|
| <TODO: error_budget_burn_fast> | <TODO: 14.4× over 1h> | P1 | <TODO: link runbook> |
| <TODO: latency_p95_breach> | <TODO: >NN ms over 10m> | P2 | <TODO: link> |
| <TODO: auth_failure_spike> | <TODO: >5% over 5m> | P3 | <TODO: link> |

## 11. Compliance posture

<TODO: matriz EU AI Act + GDPR + SOC 2.>

| Regulation | Article | Applicable | Evidence |
|---|---|---|---|
| GDPR | Art 22 (automated decision) | <TODO: si | no> | <TODO: opt-out endpoint si si> |
| GDPR | Art 30 (Records of Processing) | yes | <TODO: registro path> |
| GDPR | Art 32 (security of processing) | yes | TLS 1.3 + KMS encryption at rest |
| EU AI Act | Art 13 (transparency) | <TODO: si AI involucrado> | <TODO: AI label en response> |
| SOC 2 | CC8.1 (change management) | yes | Git commit + PR review trail |
| SOC 2 | CC7.2 (system monitoring) | yes | Prometheus + Grafana dashboards |

## 12. Rollback plan

<TODO: como revertir si C10 detecta degradacion. RTO ≤ 5 min si R4 fired.>

1. <TODO: e.g. `kubectl rollout undo deployment/{{SLUG}}` → previous image>
2. <TODO: e.g. MLflow Registry stage transition Production → Archived>
3. <TODO: e.g. feature flag flip via Unleash>
4. <TODO: verificacion smoke test post-rollback>

## 13. Open questions

<TODO: dudas no resueltas que bloquean implementacion. Si hay 0, dejar "None".>

- <TODO: question + who decides + by when>
