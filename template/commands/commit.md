---
description: Genera commit con conventional commits. Para diffs de alto blast radius dispara /voting-review-team automáticamente; con --review fuerza el gate.
allowed-tools: Bash(git status*), Bash(git diff*), Bash(git add*), Bash(git commit*), SlashCommand(/voting-review-team)
---

Analiza los cambios staged y genera un commit conventional. Para cambios de
alto impacto, gateado por `/voting-review-team` antes del commit.

## Formato del mensaje

```
<type>(<scope>): <description>

[body opcional]

[footer opcional]
```

## Types

- `feat`: nueva funcionalidad
- `fix`: corrección de bug
- `docs`: documentación
- `style`: formato (sin cambio de código)
- `refactor`: refactorización
- `perf`: mejora de rendimiento
- `test`: tests
- `chore`: mantenimiento

## Proceso

1. `git status` — ver qué está staged.
2. `git diff --staged` — analizar cambios.
3. **Trigger heurística adversarial** (ver abajo). Si dispara, correr
   `/voting-review-team <staged-diff>` y procesar veredicto antes del commit.
4. Proponer mensaje de commit conventional.
5. Esperar confirmación del usuario.
6. Ejecutar commit.
7. Si el gate corrió: `mem_save` con `type=decision` describiendo el verdict
   + advertencias diferidas + sha del commit. Trazabilidad explícita en
   Engram, no en trailer informal.

## Trigger del adversarial gate (`/voting-review-team`)

El gate se dispara automáticamente si **alguna** de las condiciones se cumple:

- `$ARGUMENTS` contiene el flag `--review` como token explícito (forzar manualmente). No se dispara por la mera presencia de la palabra `review` en el commit message libre — debe ser el flag literal precedido de espacio o al inicio.
- El diff staged toca **paths críticos**:
  - `agents/**`
  - `hooks/**`
  - `commands/**`
  - `settings.json`
  - `CLAUDE.md`
  - `.github/workflows/**`
- El diff staged supera un **umbral de tamaño**:
  - Más de 200 líneas añadidas en total, o
  - Más de 5 archivos modificados.
  - Estos números son heurística inicial. Deuda B.2.1: revalidar
    trimestralmente contra el percentil 75 del histórico de commits del
    repo. Si el ratio de gates inútiles es alto, ajustar.

Si NO se cumple ninguna condición → commit estándar sin gate (rápido).

## Cómo procesar el veredicto

`/voting-review-team` emite uno de tres labels canónicos
(`commands/voting-review-team.md:136-138`). El mapping es 1:1 — no hay
labels en español ni umbrales adicionales fuera del canon:

| Verdict | avg score | Findings | Acción |
|---|---|---|---|
| `APPROVED` | ≥ 7 | sin unanimous blockers | Continuar al paso 4. |
| `CONDITIONAL` | ≥ 5 | majority findings presentes | **Pausar.** Mostrar al usuario el resumen + las majority findings. Esperar `proceder` o `refactor`. Si `refactor` → abortar commit. Si `proceder` → continuar al paso 4 y ejecutar `mem_save` con las majority findings como deuda registrada. |
| `REJECTED` | < 5 | unanimous blockers | **Abortar commit.** Reportar:<br>`COMMIT BLOQUEADO POR /voting-review-team`<br>`Verdict: REJECTED`<br>`Avg score: <N>/10`<br>`Unanimous blockers: <list>`<br>`Acción: refactor según las findings y volver a stage + /commit.` |

> **Semántica OR canónica** (no AND): cualquiera de las dos condiciones de cada fila dispara el verdict. CONDITIONAL se activa si `avg ≥ 5` **OR** hay majority findings (no requiere ambos); REJECTED se activa si `avg < 5` **OR** hay unanimous blockers. Canon en `commands/voting-review-team.md:137-138`.

No hay un threshold separado para Adversary score — el canon usa
`avg` consensuado de los 3 reviewers. Si Adversary individual emite
score < 5 con justificación adversarial concreta y los otros dos lo
elevan a CONDITIONAL, el operador humano decide en la pausa.

## Anti-loop

- Best-effort dentro de la misma invocación de `/commit`. El runtime de
  Claude Code es stateless entre slash commands; **no hay garantía** de
  cache cross-invocation. Si se desea cache entre sesiones, debe
  implementarse como hook en
  `~/.claude/state/voting-review-cache/<sha-of-staged-diff>.json`
  (deuda B.2.2).
- Si el usuario relanza `/commit --review` con el mismo diff staged sin
  cambios y existe un verdict reciente en la sesión, mostrar el verdict
  cacheado y preguntar antes de relanzar `/voting-review-team`. No
  garantizado entre sesiones.
- Si el `/voting-review-team` falla por error técnico (no por veredicto
  adversarial — ej. `TeamCreate` falla, mailbox no entrega), permitir
  commit con flag `BYPASS_VOTING=1`. Cada bypass se registra en
  `~/.claude/state/voting-review-bypasses.log` con timestamp ISO + sha
  del staged diff + razón declarada por el usuario. Patrón consistente
  con `pr-merge-comprehension-gate.sh` (audit log de bypasses).
  - **Pre-write:** el agente que ejecuta `/commit` debe `mkdir -p
    "$(dirname ~/.claude/state/voting-review-bypasses.log)"` antes del
    primer append. Sin el `mkdir -p`, el primer bypass de un sistema
    fresco fallaría silenciosamente (no se registra el evento, perdemos
    audit trail). Patrón canónico: `hooks/pr-merge-comprehension-gate.sh`
    L74 (`mkdir -p "$(dirname "$BYPASS_LOG")"` antes de append).

## Argumentos

`$ARGUMENTS`

- Sin argumentos → análisis automático + heurística de trigger.
- Con flag `--review` (token explícito) → forzar gate aunque el diff sea pequeño.
- Con texto de mensaje libre → usarlo como base para el commit message
  (igualmente la heurística decide si gateado o no).

## Ejemplo de flujo gateado

```
$ /commit
[/commit] git diff --staged: 320 lines added across 7 files
          (incluye hooks/foo.sh, agents/bar.md)
[/commit] Trigger: high blast radius (paths críticos + tamaño).
          Disparando /voting-review-team.

[/voting-review-team] team voting-review-poc-N created
[/voting-review-team] 3 teammates analyzing staged diff...
[/voting-review-team] verdict CONDITIONAL, avg 6.5/10,
                      2 majority findings (P+A), 0 unanimous.

[/commit] CONDITIONAL → mostrando majority findings al usuario.
          Esperando: proceder | refactor

> proceder

[/commit] mem_save type=decision: "Commit gated CONDITIONAL,
          2 majority findings deferred, sha=<...>".
[/commit] Proponer mensaje:
          feat(hooks): add foo.sh + update @bar agent prompt
[/commit] Esperando confirmación final del commit message...
```

## Deudas registradas como follow-up

- **B.2.1**: revalidar el threshold 200 LOC / 5 archivos contra p75 del
  histórico de commits del repo. Trimestralmente.
- **B.2.2**: si el cache cross-invocation se vuelve necesario,
  implementar hook backing
  `~/.claude/state/voting-review-cache/<sha>.json` con TTL.
