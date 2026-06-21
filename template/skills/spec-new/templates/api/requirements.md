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

# Requirements — {{FEATURE}}

## 1. Business goal

<TODO: 1-2 frases. Que problema de negocio resuelve esta feature. Por que ahora. Coste de no hacerlo.>

## 2. Stakeholders

| Role | Identity | Concern |
|---|---|---|
| Owner | ⟦ user_name ⟧ | <TODO: e.g. ship en 2 sprints, no romper SLO> |
| Consumer (API client) | <TODO: e.g. frontend mobile, B2B partner X> | <TODO: latencia, schema stability, auth> |
| Auditor | <TODO: GDPR DPO / SOC 2 auditor / EU AI Act notified body si aplica> | <TODO: data residency, retention, audit log> |
| Maintainer (6 meses) | future-⟦ user_name ⟧ o outsider | <TODO: outsider-friendly, runbook claro> |

## 3. User stories

<TODO: 3-7 user stories format US-NNN. Cada una con role, goal, benefit.>

- **US-001** As a `<role>`, I want `<goal>` so that `<benefit>`.
- **US-002** As a `<role>`, I want `<goal>` so that `<benefit>`.
- **US-003** As a `<role>`, I want `<goal>` so that `<benefit>`.

## 4. Acceptance criteria

<TODO: numerados, medibles, binarios. Sin "deberia funcionar bien".>

- **AC-001** GIVEN `<state>`, WHEN `<action>`, THEN `<observable outcome>`.
- **AC-002** Endpoint `<METHOD /path>` returns `<status>` con schema `<ref>` para input valido.
- **AC-003** Endpoint rejects malformed input con HTTP 422 + `error.code` ∈ `<enum>`.
- **AC-004** P95 latency ≤ `<NNN ms>` bajo carga `<NNN req/s>` durante 5 min sostenidos.
- **AC-005** Auth: JWT con scope `<scope>` requerido; sin scope → HTTP 403.
- **AC-006** Rate limit: `<NNN req/min/tenant>`. Headers RFC 6585 (`X-RateLimit-*`) presentes.
- **AC-007** Error responses cumplen RFC 9457 Problem Details (type, title, status, detail).

## 5. Non-functional requirements

### 5.1 Performance

- Latency target p50/p95/p99: <TODO: NN/NN/NN ms>
- Throughput target: <TODO: NN req/s sostenidos, peak NN req/s>
- Cold start budget (si serverless): <TODO: NN ms>

### 5.2 Security

- Auth: <TODO: OAuth 2.1 + PKCE | mTLS B2B | JWT con JWKS rotation>
- Authz: <TODO: scopes granulares, RBAC, ABAC>
- Input validation: <TODO: JSON Schema 2020-12 strict, no additional properties>
- Output sanitization: <TODO: PII redaction, error message safe (no stack traces)>
- Secrets: <TODO: Vault / AWS Secrets Manager / Sealed Secrets>
- TLS: <TODO: 1.3 only, HSTS preload, mTLS interno>
- OWASP API Top 10:2023 mitigations: <TODO: lista la matriz>

### 5.3 Compliance

- GDPR Art 22 (automated decision): <TODO: aplicable si | no, justificar>
- GDPR Art 30 (Records of Processing): <TODO: registro mantenido por X>
- EU AI Act: <TODO: classification high-risk si | no; Art 13 transparency aplicable si>
- SOC 2 CC8.1 (change management): <TODO: change ticket trail>
- HIPAA: <TODO: BAA aplicable si | no>
- PCI-DSS: <TODO: aplicable si | no>

### 5.4 Observability

- Metrics: <TODO: lista metricas Prometheus + labels>
- Logs: <TODO: structured JSON, PII redacted, retention NN dias>
- Traces: <TODO: OpenTelemetry W3C Trace Context obligatorio si cross-service>
- SLO: <TODO: e.g. 99.9% availability over 30d, p95 latency <200ms>
- Alerting: <TODO: error budget burn rate, multi-window multi-burn-rate>

### 5.5 Reliability

- RTO: <TODO: NN min>
- RPO: <TODO: NN min>
- Backup strategy: <TODO: snapshot frequency + retention>
- Disaster recovery: <TODO: multi-region active-active | active-passive>
- Idempotency: <TODO: Idempotency-Key header obligatorio | no aplica>

### 5.6 Maintainability

- Outsider-friendly: outsider lee design.md + tasks.md y entiende sin rebobinar 14 ciclos.
- Documentation: OpenAPI 3.1 spec auto-generated desde codigo, drift detectado por CI.
- Test coverage target: <TODO: 80% mandatory, 90% objetivo>

## 6. Out of scope (explicit)

<TODO: lista lo que la feature NO hace. Bloquea scope creep.>

- <TODO: e.g. multi-tenancy isolation>
- <TODO: e.g. retroactive migration de data legacy>
- <TODO: e.g. internationalization de error messages>

## 7. Glossary

<TODO: terminos del dominio que no son obvios. Una linea cada uno.>

| Term | Definition |
|---|---|
| `<term>` | <TODO: definicion 1 linea> |
| `<term>` | <TODO: definicion 1 linea> |

## 8. References

- ADR linked: `docs/adr/<TODO: NNN-slug.md>`
- OpenAPI spec: `<TODO: paths/api/{{SLUG}}.yaml>`
- Related specs: <TODO: si hay deps cross-feature>
- External standards: <TODO: e.g. RFC 9457, OAuth 2.1 RFC 9700>

---

**Spec status:** Draft → completar TODOs antes de promover a `Active`. Cuando todos los TODOs esten cerrados, marca `status: Active` en frontmatter, regenera `spec.lock.json` (S4), y comitea.
