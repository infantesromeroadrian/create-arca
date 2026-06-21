---
name: clarify
description: Fuerza interrogatorio socrático (3-5 preguntas ponderadas) antes de escribir una sola línea de código. Invócame cuando ⟦ user_name ⟧ diga /clarify, no lo tengo claro, haz preguntas antes de codear, deep interview, o cuando su descripción de tarea es vaga y el código prematuro va a costar tiempo.
when_to_use: requirements ambiguos, features con múltiples interpretaciones válidas, refactors grandes donde el alcance no está fijado
argument-hint: <descripción-inicial-de-la-tarea>
disable-model-invocation: false
user-invocable: true
allowed-tools: Read Grep Glob
model: opus
effort: high
---

# /clarify — deep interview socratic pre-código

⟦ user_name ⟧ pidió clarificar: `$ARGUMENTS`

Inspirado en el **Deep Interview mode** de oh-my-claudecode. Principio: código escrito con requirements ambiguos es deuda garantizada. @sensei lleva años predicando que "preguntar bien" es la skill más infravalorada en ingeniería. Este skill la aplica sistemáticamente.

## Preflight

1. Si `$ARGUMENTS` es literalmente una pregunta ya concreta ("cómo uso X con Y") → saltate esto, no aplica — responde directo.
2. Si la tarea es crítica o de producción → sube el rigor (5 preguntas, no 3).
3. Si la tarea parece clara pero ⟦ user_name ⟧ pidió `/clarify` igual → respeta — siempre hay un supuesto oculto.

## Proceso (1 round, explícito)

### Fase 1 · Scanner silencioso (no emitas aún)

Antes de preguntar, escanea lo observable:
- `$ARGUMENTS` — el texto literal de ⟦ user_name ⟧
- Archivos recientes modificados en el repo (`git log -5 --name-only`)
- Tareas activas (`cat .claude/state/current-task.md` si existe)
- Memory relevante (skills/personal notes si aplica)

Esto NO sustituye las preguntas — informa su calidad. Evita preguntar lo ya obvio ("¿qué lenguaje?" cuando es un repo Python puro).

### Fase 2 · Interrogatorio (3-5 preguntas ponderadas)

Dimensiones a cubrir (selecciona las 3-5 de mayor peso para esta tarea):

| Dimensión | Pregunta tipo |
|---|---|
| **Criterio de éxito** | "¿Cómo sabremos que está terminado? ¿Qué medimos?" |
| **Alcance** | "¿Esto incluye X e Y, o solo X?" |
| **Usuarios/consumidores** | "¿Quién usa esto y con qué frecuencia?" |
| **Restricciones ocultas** | "¿Hay compatibilidad con Z, plazos, presupuesto de tokens/coste?" |
| **Trade-offs aceptados** | "¿Prefieres simple y limitado, o flexible y complejo?" |
| **Comportamiento en error** | "Si falla, ¿falla ruidoso, silencioso, o tiene fallback?" |
| **Reversibilidad** | "¿Es reversible este cambio o irreversible (schema migration, delete, push)?" |
| **Dependencias futuras** | "¿Qué viene después de esto que dependa de cómo lo hagamos?" |

Formato:

```markdown
**Clarificación previa al código:**

Antes de escribir nada, necesito entender {N} cosas:

1. **{dimensión}** — {pregunta concreta, no retórica}. Si no lo sabes: {opción A | opción B | opción C} — elige.
2. ...

Responde en cualquier orden. Si alguna pregunta está mal planteada, dímelo.
```

### Fase 3 · Espera

**No escribas código**. No propongas diseño. No delegues a otros agents. Espera respuestas de ⟦ user_name ⟧.

Si ⟦ user_name ⟧ responde solo algunas preguntas → re-pregunta las pendientes con más contexto de lo que ya dijo.
Si ⟦ user_name ⟧ dice "no sé" a alguna → propón 2-3 opciones concretas con pros/contras y que elija.
Si ⟦ user_name ⟧ pide "tú decide" → toma la decisión por él explícitamente (como arquitecto) y márcala como "decisión por default, revisable".

### Fase 4 · Síntesis

Cuando tengas respuestas suficientes:

```markdown
**Spec cerrada:**

- Criterio de éxito: {…}
- Alcance: IN {…}, OUT {…}
- Restricciones: {…}
- Trade-offs aceptados: {…}
- Plan propuesto: {3-5 bullets del approach}

¿Confirmas para empezar?
```

Si ⟦ user_name ⟧ confirma → delegar al pipeline/agent correspondiente con esta spec compresada.

## Reglas duras

- **No escribir código en este skill**. Este skill es exclusivamente para convertir tarea vaga → spec cerrada. Cualquier implementación va después, en otro skill/agent.
- **Máximo 5 preguntas**. Más que eso es obsesión burocrática, no clarity. Si después de 5 sigue ambiguo, el problema es del enunciado, no del número de preguntas.
- **Preguntas concretas, no retóricas**. Mal: "¿has pensado en los usuarios?". Bien: "¿usuarios internos (5-10), externos (100-1000), o público (sin login)?".
- **No interrogar sobre lo evidente**. Si el repo es Python 3.12 con ruff, no preguntes el lenguaje.

## Anti-uso

Este skill NO se usa cuando:
- ⟦ user_name ⟧ ya dio requirements detallados — respeta, no bureaucratices.
- La tarea es trivial (un fix, un rename, una pregunta).
- Estás en medio de un pipeline donde C1 Discovery `@project-planner` ya hizo el trabajo.

**ultrathink** al seleccionar las preguntas. Hacer las 3 preguntas que más reducen incertidumbre vale más que las 5 más fáciles de formular.
