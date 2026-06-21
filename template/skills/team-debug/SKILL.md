---
name: team-debug
description: Team preset para sesiones de debug — 3 teammates en paralelo (hipótesis, reproducción, root cause). Invócame cuando ⟦ user_name ⟧ diga /team-debug, debuggeamos en equipo, no encuentro el bug, o está atascado >30 min en un bug.
when_to_use: bugs donde una sola línea de razonamiento no progresa (intermitentes, producción, sistemas distribuidos)
argument-hint: <descripción-del-bug + síntomas-observados>
disable-model-invocation: false
user-invocable: true
allowed-tools: Read Grep Glob Bash(git log *) Bash(gh *)
model: opus
effort: high
---

# /team-debug — agent team 3 perspectivas debug

⟦ user_name ⟧ está atascado en: `$ARGUMENTS`

Inspirado en wshobson agent-teams "debug" preset + Ralph verify-fix. Requiere `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`.

## Preflight

1. Si `$ARGUMENTS` es vago → pedir síntomas observables: mensaje de error exacto, stacktrace, cuándo se dispara, qué esperaba vs qué pasa.
2. Si el bug es intermitente → flag alto, los 3 teammates deben considerar race conditions y no-determinismo.

## Team (3 teammates en paralelo)

| Teammate | Agent | Foco |
|---|---|---|
| **hypothesis** | `code-critic` | genera 5 hipótesis ranked por probabilidad, busca patterns en git log relacionados |
| **reproducer** | `tester` | construye test mínimo que reproduce el bug consistentemente, o explica por qué no se puede |
| **root-cause** | `chief-architect` | si hypothesis hits y reproducer valida, explica causa raíz arquitectónica (no el síntoma) |

## Flujo

### Round 1 — hypothesis + reproducer en paralelo

Ambos arrancan con el mismo input (síntomas + stacktrace). Reproducer NO espera a hypothesis — trabaja independiente buscando test mínimo.

### Round 2 — cross-fire

Cuando ambos emiten:
- `hypothesis` lee el test del reproducer → descarta hipótesis incompatibles con lo reproducido
- `reproducer` lee hipótesis top → ajusta test para discriminar entre las top 2

### Round 3 — root-cause

Con hipótesis top-2 + test reproducible → `root-cause` decide cuál es la explicación estructural. Emite:
- **causa raíz** (1 frase)
- **por qué no se detectó antes** (gap de test/monitoring/revisión)
- **fix propuesto** con scope mínimo

## Output

```markdown
## /team-debug — {bug}

### Reproducción
- test: {file:line o comando}
- determinístico: sí/no (razón si no)

### Hipótesis top-3
1. [confirmada] {descripción} — evidencia: {file:line, git commit}
2. [descartada] {por qué}
3. [pendiente verificar] {cómo verificar}

### Causa raíz
{1 frase}. **Por qué no se detectó**: {gap}. **Fix scope mínimo**: {qué tocar}.

### Próximo paso
- Delegar fix a {agent} con esta spec
- O, si fix es trivial: aplicar directamente + verify
```

## Reglas

- No terminar sin reproducción real o explicación de por qué es irreproducible.
- Root-cause apunta a arquitectura, no al síntoma ("X es null" → por qué nadie validó que X se inicializase).
- Si los 3 teammates no convergen tras Round 3 → escalar a ⟦ user_name ⟧ con 2 opciones alternativas.

**ultrathink** en root-cause. Los bugs que llegan a `/team-debug` ya tuvieron un intento individual fallido — el valor aquí es la arquitectura del análisis, no buscar más random.
