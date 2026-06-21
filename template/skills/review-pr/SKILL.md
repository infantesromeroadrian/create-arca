---
name: review-pr
description: Revisión completa de PR con múltiples agents en paralelo. Invócame cuando ⟦ user_name ⟧ diga review pr, revisa este pr, check this PR, o similar, antes de merge.
when_to_use: tras abrir PR en github o pedir revisión crítica multi-agente
argument-hint: [PR-number | PR-url | opcional si ya estás en branch del PR]
disable-model-invocation: false
user-invocable: true
allowed-tools: Bash(gh pr *) Bash(git diff *) Bash(git log *) Read Grep Glob
model: opus
effort: high
---

# /review-pr — revisión multi-agente paralela

⟦ user_name ⟧ pidió revisar el PR `$ARGUMENTS`.

## Guardas de scope (preflight)

1. Si `$ARGUMENTS` está vacío → intenta detectar PR desde la rama actual: `gh pr view --json number,title,headRefName`. Si falla, pide explícitamente a ⟦ user_name ⟧ el número o URL.
2. Si el PR tiene >500 líneas de diff, avisa a ⟦ user_name ⟧ antes de continuar (coste alto en Opus).

## Dynamic context

Preprocessing — dato live del PR antes de delegar:

!`gh pr view $ARGUMENTS --json title,author,additions,deletions,changedFiles,headRefName,baseRefName 2>/dev/null || echo "PR resolution pending"`

Changed files:

!`gh pr diff $ARGUMENTS --name-only 2>/dev/null | head -30 || true`

## Proceso (3 reviewers en paralelo)

Lanza simultáneamente vía Task tool:

1. **@chief-architect** — arquitectura, SOLID, acoplamiento, patrones, coherencia con ADRs del repo.
2. **@python-specialist** — typing moderno, logging estructurado, error handling, antipatrones Python (si el PR toca `.py`). Si no, **skip este reviewer**.
3. **@ai-red-teamer** — vulnerabilidades, secretos expuestos, inyección, OWASP Top 10. Carga skill `owasp-security`.

Si el PR toca ML/DL/AI código específico, añade un 4º reviewer:

4. **@math-critic** — correctness matemática, gradientes, stability numérica, métricas con IC.

## Formato de output (estricto)

```markdown
## PR Review — #<num>

### [ALERT] BLOQUEANTE
- <fichero:línea> — descripción + qué hacer. (si no hay → "Ninguno.")

### [WARN] RECOMENDADO
- ...

### 💡 OPCIONAL
- ...

### Veredicto
**APROBADO** | **BLOQUEADO** — 1-2 frases resumen.
```

## Reglas duras

- **No apruebas** si hay al menos 1 BLOQUEANTE.
- Si `@ai-red-teamer` reporta secreto expuesto → BLOQUEANTE automático, sin negociación.
- No menciones el proceso — solo output final.
- **ultrathink** en el paso de síntesis para reconciliar findings de los 3+ reviewers.

## Integración con workflow self-hosted runner

Este skill también es invocable desde el workflow `pr-review.yml` (trigger `@claude review` en comments de PR). El guard `disable-model-invocation: true` asegura que solo se dispara manualmente, no por auto-detection.
