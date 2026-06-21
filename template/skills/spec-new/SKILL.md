---
name: spec-new
description: Crea un Spec-Driven Development bundle para una feature regulada/contract-bound. Genera docs/specs/<feature>/{requirements,design,tasks}.md + spec.lock.json (SHA256 fingerprint). Solo activar cuando los triggers R1-R4 de ADR-027 disparen. Invocame con /spec-new <type> <feature-name>.
when_to_use: tras decision arquitectural (ADR firmado) en C4 Design para features que cumplen ADR-027 trigger matrix R1 (API contract) / R2 (regulated+PII) / R3 (cross-context) / R4 (C10 RTO ≤5min). NUNCA en C2 EDA / C3 Hypothesis / C5 POC / bug fix <50 LOC / refactor sin contract change / HTB.
argument-hint: "<type: api|ml|rag|agent> <feature-name en kebab-case>"
disable-model-invocation: false
user-invocable: true
allowed-tools: Bash
model: sonnet
effort: medium
---

# /spec-new — Spec-Driven Development bundle (ADR-027 S2)

Implementa la skill `/spec-new` definida en ADR-027 (hybrid Spec-Driven Development adoption). Genera el bundle SDD canonico de Spec Kit (requirements + design + tasks) en formato Markdown, mas un `spec.lock.json` con SHA256 deterministico que el hook `spec-drift-detector.sh` (S4) usara para detectar drift entre spec y codigo.

## Cuando usarlo

Solo si CUALQUIERA de los triggers ADR-027 dispara para la feature:

| Rule | Test |
|---|---|
| R1 | Feature expone API contract (OpenAPI 3.1, gRPC, MCP tool schema) |
| R2 | Toca PII / GDPR Art 22 / EU AI Act high-risk / SOC 2 in-scope data |
| R3 | Integra ≥ 2 bounded contexts (cross-team o cross-project) |
| R4 | C10 deploy con rollback critico (RTO ≤ 5 min) AND user-facing |

Si ninguno → fast-track ARCA actual, NO usar `/spec-new`.

## Cuando NO usarlo

- C2 Data EDA, C3 Hypothesis, C5 POC — exploratory phases (anti-pattern).
- Bug fixes <50 LOC sin cambio de contract.
- Refactors internos que preservan behaviour observable.
- HTB / red-team work (`rules/pipeline-htb.md` es disciplina propia).
- `@arca-ambient-monitor` Track B work (meta-pipeline, no feature).
- ANTES de tener ADR firmado en `docs/adr/NNN-*.md`.

## Sintaxis

```
/spec-new <type> <feature-name>
```

- `<type>` ∈ `{api, ml, rag, agent}`. Selecciona la plantilla a renderizar.
- `<feature-name>` kebab-case, slugificado automaticamente. Min 5 chars utiles.

Ejemplos:

- `/spec-new api user-export-gdpr`
- `/spec-new ml fraud-detection-classifier-v2`
- `/spec-new rag legal-corpus-retrieval`
- `/spec-new agent customer-support-triage`

## Flujo del run.sh

1. Validar `$ARGUMENTS` partido en 2 tokens: `type` + `feature-name`. Rechazar si falta uno o sobra.
2. Validar `type` esta en `{api, ml, rag, agent}` (otros types reservados para futuras fases).
3. Sanitizar `feature-name` a slug kebab-case (mismo algoritmo que adr-new).
4. Validar `docs/specs/` existe (crear con README si no).
5. Validar `docs/specs/<slug>/` NO existe (no overwrite — abort si existe).
6. Localizar templates en `~/.claude/skills/spec-new/templates/<type>/{requirements,design,tasks}.md`.
7. Crear `docs/specs/<slug>/`.
8. Renderizar las 3 plantillas sustituyendo `{{FEATURE}}`, `{{TYPE}}`, `{{DATE}}`, `{{SLUG}}`, `{{ADR_PLACEHOLDER}}` (este ultimo deja `<TODO: link to ADR-NNN>` para que el autor lo rellene).
9. Computar SHA256 de cada archivo renderizado.
10. Escribir `spec.lock.json` con metadata + hashes.
11. Avisar a ⟦ user_name ⟧ de los paths creados + proximos pasos (rellenar prosa, linkear ADR, /justify).

## Anti-patterns explicitos

- NO crear `/spec-new` sin ADR previo en `docs/adr/`. La spec referencia decisiones, no las decide.
- NO usar para features fast-track. Si dudas, no actives la skill — el coste de ARCA fast-track no compensa la rigidez SDD para POCs.
- NO duplicar contenido del ADR en `design.md`. design.md LINKEA al ADR-NNN; si el contenido es el mismo, vive en el ADR.
- NO editar `spec.lock.json` a mano. Se regenera con `bash skills/spec-new/run.sh --rehash <feature>` (S4 entregable).

## Sanity checks que hace run.sh

- 2 argumentos obligatorios.
- type valido.
- slug no vacio tras sanitize.
- `docs/specs/` accesible.
- `<slug>/` no existe.
- Templates existen para el type pedido.
- Escritura atomica de `spec.lock.json` (tmp + rename).

## Edge cases conocidos

- type no soportado → abort con lista de types validos.
- feature-name unicode → sanitize lo descarta; abort si todo unicode.
- `docs/specs/<slug>/` colision → abort, no overwrite. Para regenerar, borrar manualmente.
- Templates desactualizadas (faltan placeholders) → run.sh las renderiza tal cual; @maintainability-engineer en C8 detectara.

## Coordinacion ARCA

- `@architect-ai` invoca `/spec-new` tras firmar ADR en C4 si triggers R1-R4 disparan.
- `@api-designer` invoca `/spec-new api` cuando produce OpenAPI 3.1 spec en C4 (extension natural — su workflow ya es spec-first).
- `@code-critic` audita el run.sh antes de promover a `Accepted` en S6.
- `@maintainability-engineer` audita las plantillas en S6 para outsider-friendliness.
- Hook `spec-drift-detector.sh` (S4) consume `spec.lock.json` para verificar coherencia.

## Stats (futuro S4)

`~/.claude/state/spec-new-stats.json` tracking buckets:

| bucket | cuando |
|---|---|
| `created` | `/spec-new` creo bundle exitoso |
| `aborted_existing` | bundle ya existia |
| `aborted_invalid_type` | type no soportado |
| `aborted_invalid_args` | argumentos malformados |

## Referencias

- ADR-027: `docs/adr/027-hybrid-sdd-adoption.md`
- Patron heredado: skill `adr-new` (`~/.claude/skills/adr-new/`)
- GitHub Spec Kit: github.com/github/spec-kit
- Plantillas Spec Kit canonicas: requirements.md / design.md / tasks.md
