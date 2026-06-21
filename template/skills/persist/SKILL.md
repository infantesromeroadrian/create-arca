---
name: persist
description: Envuelve cualquier tarea en un loop verify→fix hasta convergencia — no acepta "parcialmente hecho". Invócame cuando ⟦ user_name ⟧ diga /persist, no cierres hasta que pase, asegurate de que queda bien, termina esto completamente, o similar.
when_to_use: tareas donde "casi hecho" no vale (fix crítico, merge antes de release, resolver flaky test, cerrar TODO real)
argument-hint: <descripción breve de la tarea a completar>
disable-model-invocation: false
user-invocable: true
allowed-tools: Read Grep Glob Edit Write Bash
model: opus
effort: high
---

# /persist — modo persistencia (no parcial)

⟦ user_name ⟧ pidió persistencia sobre: `$ARGUMENTS`

Inspirado en el **Ralph mode** de oh-my-claudecode. La filosofía: Opus 4.8 a veces deja tareas "casi hechas" — compila, tests pasan pero el comportamiento real no está probado, o 3 de 4 casos cubiertos. En modo `/persist`, la tarea NO se cierra hasta que el loop verify→fix converge.

## Preflight

1. Si `$ARGUMENTS` vacío → pide a ⟦ user_name ⟧ descripción concreta + criterio de éxito medible. Sin criterio no hay loop — aborta.
2. Si la tarea es exploratoria (investigación, pregunta, brainstorm) → avisa que `/persist` no es el modo adecuado, sugiere delegar a @sensei.
3. Si la tarea es ambigua ("mejora esto") → fuerza concreción: qué métrica, qué comportamiento esperado, qué test confirmaría.

## Loop (máx 5 iteraciones)

Cada iteración ejecuta 4 fases:

### 1. EXECUTE

Aplica el cambio o siguiente paso del plan. Edit / Write / Bash según necesite. Sin pedir permiso entre sub-pasos dentro de la misma iteración — ya autorizado al invocar `/persist`.

### 2. VERIFY

Ejecuta el criterio de éxito medible. Según naturaleza de la tarea:

- **Código Python**: `pytest path/to/test_*.py -v` + `ruff check` + mypy si aplica
- **Bash/scripts**: ejecución end-to-end del flujo
- **Fix de bug**: reproducir el bug original → debe fallar; aplicar fix → debe pasar
- **Refactor**: tests existentes siguen verdes + behavior inchanged
- **CI failure**: `gh run view <id> --log-failed | tail` debe estar limpio en próxima run
- **PR review finding**: el finding específico debe estar abordado (archivo:línea)

Si VERIFY pasa → salta a COMMIT. Si falla → FIX.

### 3. FIX

Con el output exacto del VERIFY fallido, aplica corrección dirigida. **NO** hagas cambios cosméticos "por si acaso" — solo aborda la razón concreta del fallo.

### 4. LOOP CHECK

Si iteración <5 y VERIFY aún falla → vuelve a EXECUTE con lo aprendido. Si iteración ==5 sin pasar → **ABORT** con reporte explícito: qué intentaste, qué falla queda, qué crees que necesita (intervención humana, cambio de approach, más contexto).

### 5. COMMIT

Cuando VERIFY pasa:
1. `git diff` para mostrar el cambio final a ⟦ user_name ⟧.
2. Si la tarea lo requería, crear commit con mensaje que cite el criterio verificado.
3. Si era fix de CI, pushear y esperar (Monitor) el run verde antes de cerrar.

## Reglas duras (no negociables)

- **No declarar "done" sin VERIFY verde**. Si no puedes correr el verify (ej. falta infra), abortar con reporte — no mentir que está hecho.
- **No cambiar el criterio de éxito** a mitad del loop para que pase artificialmente. Si el criterio estaba mal, abort y redefine con ⟦ user_name ⟧.
- **No skip tests** (`-x`, `--lf`, `--no-verify`). Si un test es flaky, abordar la flakiness es parte de la tarea.
- **Máximo 5 iteraciones**. Si a la 5 no converge, el problema es otro (approach, requirements, conocimiento) — escalar, no iterar más.
- **Cada FIX tiene que cambiar algo medible**. Si dos iteraciones aplican el mismo cambio con leve variación, eso es señal de loop estéril — abort.

## Integración con otros gates ARCA

Si la tarea produce código, la cadena completa sigue siendo:

```
/persist EXECUTE → @math-critic (si ml/dl/ai-engineer) → @debt-detector → @code-critic → VERIFY → COMMIT
```

El loop `/persist` no sustituye los gates — los envuelve. Los gates son la definición del criterio VERIFY para código.

## Output esperado

Al cerrar (éxito o abort), reporte en 4 secciones:

```markdown
## /persist — {tarea}

### Iteraciones
1. EXEC: {qué hiciste} → VERIFY: {resultado}
2. ...

### Resultado
- [éxito] VERIFY pasó en iter N. Criterio: {qué se midió}.
- [abort] 5 iteraciones sin converger. Último blocker: {razón}. Recomendación: {qué humano debe hacer}.

### Commit / próximo paso
- sha / url del commit si aplica
- si abort, qué retomar después
```

**ultrathink** antes de declarar éxito en la iter final — opus tiende a confundir "compila" con "funciona". La pregunta clave: ¿el comportamiento esperado por ⟦ user_name ⟧ existe, o solo la sintaxis del cambio existe?
