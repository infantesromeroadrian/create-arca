---
name: skill-effectiveness
description: Aggregate the JSONL skill-telemetry log over a configurable window and flag skills whose success_rate sits below a threshold as CANDIDATES for manual review. NEVER auto-rewrites — ⟦ user_name ⟧ sign-off is non-negotiable.
when_to_use: weekly, after Guardian Audit, or on demand when a skill feels off and ⟦ user_name ⟧ wants the numbers
argument-hint: "[--weeks N] [--threshold X]"
disable-model-invocation: false
user-invocable: true
allowed-tools: Bash
model: sonnet
effort: low
---

# /skill-effectiveness — Hermes-3 Idea 3

Closes the loop on skill quality with arithmetic, not LLM judgment.
The hook `hooks/skill-telemetry.sh` records every skill invocation as
a JSONL line; this skill folds those lines into a weekly report and
flags skills below threshold for **manual** review.

Idea 3 is deliberately conservative versus the Hermes "skill
self-improvement during use" pattern: ARCA does not auto-rewrite. The
report is data; ⟦ user_name ⟧ is the loop closer.

## Cuando usarlo

- Cierre semanal del Guardian Audit — invoca `/skill-effectiveness`
  con defaults (`--weeks 4 --threshold 0.7`).
- Sospechoso de regresion en una skill concreta — abre la ventana
  (`--weeks 8`) y baja el umbral (`--threshold 0.5`) para verla en
  contexto historico.
- Antes de proponer un rewrite de skill — el report es el evidence
  pack que va al `@prompt-engineer`.

## Cuando NO usarlo

- Para decidir auto-rewrite. No se hace. Ni con LLM-as-judge ni con
  threshold extremo. ⟦ user_name ⟧ decide.
- Sobre semanas con <10 invocaciones por skill — el `MIN_TOTAL_FOR_FLAG`
  filtra esos casos por construccion, pero ejecutar contra periodos
  vacios solo produce reports inutiles.

## Flujo

1. Slash command captura `$ARGUMENTS` con heredoc canonico
   (ARCA-SEC-1) y rechaza multi-line.
2. `run.sh` parsea `--weeks N --threshold X` desde stdin.
3. Lee `~/.claude/state/skill-telemetry.jsonl`.
4. Filtra registros con `ts >= now - weeks*7d` via
   `strptime("%Y-%m-%dT%H:%M:%S%z") | mktime` (acepta offsets `+HH:MM`,
   no solo Z).
5. Agrupa por skill y cuenta `total / success / fail / unknown`.
6. `success_rate = success / (success + fail)` — `unknown` queda
   excluido del denominador.
7. Flag rule:
   ```
   flag iff (success + fail + unknown) >= 10  AND  success_rate < threshold
   ```
8. Escribe `~/.claude/state/skill-effectiveness/<YYYY-Www>.md` con
   header, tabla de flagged skills (sorted asc por rate) y texto
   explicito sobre ⟦ user_name ⟧ sign-off.
9. Incrementa stats en `hooks/lib/skill-telemetry-stats.sh`
   (`effectiveness_runs`, `weeks_processed`, `flagged_skills_total`,
   `unique_skills`).

## Invocacion

Toda la logica ejecutable vive en `skills/skill-effectiveness/run.sh`.
El skill y el slash command (`commands/skill-effectiveness.md`) son
punteros al mismo script. El bash block usa el patron canonico ADR-007
(ARCA-SEC-1): heredoc con delimitador entre comillas simples — bash no
expande `$(...)`, backticks ni variables dentro. El payload aterriza
literal en `ARGS_RAW` y de ahi pasa por stdin a `run.sh`.

```bash
ARGS_RAW=$(cat <<'ARCA_SKILL_EFF_EOF'
$ARGUMENTS
ARCA_SKILL_EFF_EOF
)
ARGS_RAW="${ARGS_RAW%$'\n'}"

case "$ARGS_RAW" in
  *$'\n'*)
    echo "[/skill-effectiveness] ENTORNO: argumentos multi-linea no permitidos (ARCA-SEC-1 B1)." >&2
    exit 2
    ;;
esac

printf '%s' "$ARGS_RAW" | bash "${CLAUDE_PROJECT_DIR:-${PWD}}/skills/skill-effectiveness/run.sh"
```

Por que stdin y no argv: el script no expone argv para minimizar la
superficie. /justify usa la misma convencion (ADR-007).

## Outcome proxy v1

Derivado del `tool_response` del propio Skill call:

| Senal | Outcome |
|---|---|
| `tool_response.is_error == true` | fail |
| `tool_response.error` truthy | fail |
| `tool_response.success == false` | fail |
| `tool_response` presente sin error marcado | success |
| `tool_response` ausente / vacio | unknown |

`unknown` se excluye del denominador de `success_rate` para no
penalizar skills cuyo runtime no anota la respuesta.

## Outcome proxy v2 (FUTURO — ARCA-DEBT-004)

Una senal mas precisa correlaria la invocacion con la actividad de
los 60 segundos siguientes:

- Edit/Write/MultiEdit revertido en la ventana → fail
- Bloqueo de `forced-justification.sh` → fail
- Rechazo de `@code-critic` → fail
- Sin actividad antagonica → success (o se mantiene v1)

Requiere un correlator separado (tail+watch sobre el JSONL + stream
de PostToolUse posteriores). v1 es suficiente para arrancar la loop
y validar que ⟦ user_name ⟧ usa el reporte; v2 entra cuando v1 deja de ser
discriminante.

## Anti-rewrite policy

NUNCA auto-rewrite. El reporte solo identifica candidatos. La
secuencia para reescribir una skill flageada es:

1. ⟦ user_name ⟧ lee el report y decide si la skill merece atencion.
2. Si si: escala a `@prompt-engineer` con el report como evidence pack.
3. `@prompt-engineer` propone redraft.
4. `@code-critic` revisa el cambio.
5. ⟦ user_name ⟧ aprueba el merge.

Saltarse cualquier paso = pecado mortal #4 (arquitectura sin ADR / sin
justificacion). El skill no puede iniciar el rewrite por si solo, ni
siquiera con threshold extremo, ni siquiera con N alto. La loop es
human-in-the-loop por diseno (memo `docs/roadmap/hermes-agent-inspirations.md`,
Idea 3 caveat).

## Stats

`~/.claude/state/skill-telemetry-stats.json` se actualiza:

| bucket | cuando |
|---|---|
| `total_invocations` | hook `skill-telemetry.sh` registro un PostToolUse:Skill |
| `unique_skills` | suma de skills-distintas-por-ventana (window appearances, NO lifetime-únicas — 10 runs sobre 20 skills suman 200, no 20) |
| `weeks_processed` | `/skill-effectiveness` escribio un reporte semanal |
| `effectiveness_runs` | invocacion de `/skill-effectiveness` (bump siempre) |
| `flagged_skills_total` | suma de skills flageadas a lo largo de runs |

Inspeccionar:

```bash
jq . ~/.claude/state/skill-telemetry-stats.json
```

## Edge cases conocidos

- Telemetria vacia o JSONL inexistente → reporte con tabla vacia y
  mensaje "No skills below threshold this period."
- Skill con `success + fail == 0` (todo `unknown`) → no flageable por
  construccion (denominador 0). Aparece en `unique_skills` count pero
  no en flag list.
- Records con timestamp no parseable → silently dropped. JSONL es
  append-only; un line malformado no debe envenenar el reporte.
- Threshold fuera de `(0, 1]` → `run.sh` aborta con exit 1.
- `--weeks` no positivo → exit 1.
- Multi-line en `$ARGUMENTS` → guard del slash command exit 2 antes
  de tocar `run.sh`.

## ARCA-DEBT-001 (5-way) referenciada

`hooks/lib/skill-telemetry-stats.sh` es el quinto sibling del patron
de stats helpers. Comparte el race window read-modify-write con sus 4
hermanos (`justification-stats.sh`, `auto-adr-stats.sh`,
`diff-comprehension-stats.sh`, `engram-nudge-stats.sh`). Counters son
observability, no decision input → race aceptado. Migrar a `flock`
solo si alguna vez disparan alerting.
