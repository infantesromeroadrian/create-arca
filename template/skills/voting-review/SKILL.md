---
name: voting-review
description: Review adversarial en paralelo con 3 perspectivas (Pragmatist, Architect, Adversary) como agent team real — lo que diferencia esto de subagents normales es el CROSSFIRE round donde cada teammate challenges findings del resto vía mailbox. Invócame cuando ⟦ user_name ⟧ diga voting review, /voting-review, review adversarial, o similar.
when_to_use: decisiones críticas (seguridad, arquitectura, refactors grandes) donde un solo punto de vista no basta
argument-hint: <target> [--mode security|architecture|quality]
disable-model-invocation: false
user-invocable: true
allowed-tools: Read Grep Glob Bash(git diff *) Bash(gh pr *) Bash(gh api *)
model: opus
effort: xhigh
---

# /voting-review — agent team adversarial (3 reviewers con crossfire)

⟦ user_name ⟧ pidió review adversarial sobre: `$ARGUMENTS`

## Por qué es un agent team y no 3 subagents

Subagents paralelos → 3 reports aislados, el lead los concatena. **Resultado: 3 monólogos**.
Agent team → los 3 teammates comparten task list + mailbox. **Resultado: confrontación adversarial real** — cada uno lee findings de los otros y challenges los débiles antes de firmar.

Este skill requiere `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` (ya en settings).

## Preflight

1. Si `$ARGUMENTS` vacío → pide target explícito (PR#, path, commit-sha).
2. Parsea `--mode` si aparece. Default: `quality` (3 perspectivas mixtas).
3. Si el target es un PR → dynamic context:

!`gh pr view $ARGUMENTS --json title,additions,deletions,changedFiles 2>/dev/null || echo "target no es PR — trato como path/sha"`

## Composición del team

**Lead**: el orquestador que lanza la skill (Opus). No puntúa, solo sintetiza.

**Teammates** (los 3 van en paralelo al inicio):

| Teammate | Subagent | Perspectiva | Foco |
|----------|----------|-------------|------|
| **pragmatist** | `code-critic` | producción | edge cases, perf, data validation, error handling |
| **architect** | `chief-architect` | estructural | SOLID, coupling, escalabilidad, deuda técnica |
| **adversary** | `ai-red-teamer` | seguridad | OWASP, injection, secretos, auth bypass |

## Flujo — 3 rounds

### Round 1 · Discovery (paralelo)

Usa `TaskCreate` para cada teammate con su foco específico. Los 3 trabajan simultáneamente sin ver output del resto. Cada uno produce `findings-<teammate>.md` con:

- Score 1-10 en su eje
- Lista de findings con `file:line`
- Marca cada finding como **BLOQUEANTE / RECOMENDADO / OPCIONAL**

### Round 2 · Crossfire (adversarial — el diferenciador clave)

Cuando los 3 completan Round 1, **usa `SendMessage`** para que cada teammate reciba los findings de los otros 2 con este prompt explícito:

> "Lee los findings de los otros 2 reviewers. Para cada finding suyo: (a) ¿estás de acuerdo? (b) ¿lo subirías o bajarías de severidad? (c) ¿ves un ángulo que se les escapó en este mismo finding? Sé específico. Si un finding del adversary dice 'SQL injection' pero el pragmatist dice 'está parametrizado', el architect tiene que decidir con evidencia del código, no por compromiso."

Cada teammate emite un `crossfire-<teammate>.md` con su veredicto sobre cada punto ajeno.

### Round 3 · Synthesis (lead)

El lead lee los 6 artefactos (3 findings + 3 crossfire) y categoriza:

- **Unanimous** → los 3 de acuerdo tras crossfire → peso máximo
- **Majority** → 2 de acuerdo, 1 discrepa con justificación → peso medio
- **Contested** → discrepancia real no resuelta → flag para ⟦ user_name ⟧, no cerrar
- **Withdrawn** → finding retirado tras crossfire → no reportar

## Hooks del team (ya disponibles en settings si se activan)

- `TeammateIdle` → si un teammate marca idle antes de completar crossfire, devolver con feedback "falta revisar findings de <otro>".
- `TaskCreated` → validar que cada task tiene `<teammate>:round<n>` en el subject.
- `TaskCompleted` → bloquear cierre de task si el artefacto esperado no existe.

## Output final

```markdown
# Voting Review — <target>

## Scores (post-crossfire)
| Perspectiva | Score | Findings confirmados | Retirados | Adjustados |
|-------------|-------|----------------------|-----------|------------|

## Unanimous (bloqueante si severidad alta)
- <file:line> — <descripción> — severidad.

## Majority (con disidencia registrada)
- <file:line> — <descripción>. Disiente: <teammate> porque <razón>.

## Contested (requiere decisión de ⟦ user_name ⟧)
- <file:line> — <descripción>. Positions: <p1> vs <p2>.

## Verdict
APPROVED ≥7 avg y 0 unanimous BLOQUEANTE.
CONDITIONAL ≥5 o con majority BLOQUEANTE.
REJECTED <5 o con unanimous BLOQUEANTE.

## Retrospectiva del team
- ¿Qué finding NO habría aparecido sin el crossfire? (mide el valor del formato agent team vs 3 subagents paralelos).
```

## Modos

- **security** — los 3 teammates cambian a perspectivas security: `ai-red-teamer` (script-kiddie), `ai-red-teamer` (researcher), `ai-red-teamer` (insider). Diferentes amenazadores, no ejes.
- **architecture** — los 3 desde ejes diferentes: maintainer (código legacy), scaler (10x carga), newcomer (primer día en el repo).
- **quality** (default) — pragmatist + architect + adversary (la tabla principal arriba).

## Persistencia

Guarda verdict + findings unanimous a Engram con tag `voting-review`. Útil para trend: si los mismos issues aparecen 3 reviews seguidas → deuda sistémica.

**ultrathink** en Round 3. El crossfire ya hizo el trabajo sucio, pero la categorización final (Unanimous vs Contested) requiere juicio — no es aritmético, es semántico. Un finding puede tener 3 votos pero referirse a cosas distintas.

## Fallback si agent teams no está disponible

Si `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` no está en el env → warn a ⟦ user_name ⟧, y caer al modo legacy (`commands/voting-review.md` = 3 subagents paralelos sin crossfire). El crossfire se pierde, pero los 3 reports llegan igual.
