---
description: Auditoría exhaustiva de la config de Claude Code (settings.json, hooks, skills, commands) contra la doc oficial Anthropic. Detecta drift, campos undocumented, env vars que dejaron de exportarse. Idempotente por día — usa --force para regenerar.
---

# /claude-config-audit

Lanza el audit semanal de la config de Claude Code. Mismo motor que el cron del lunes 7AM. Útil tras un upgrade del CLI, antes de un cycle close, o cuando un bug huele a runtime drift.

## Uso

```
/claude-config-audit              # idempotente — reusa report del día si existe
/claude-config-audit --force      # regenera el report aunque haya uno del día
```

## Qué hace

1. Lee `skills/claude-config-audit/SKILL.md` con el checklist de 20 puntos.
2. Delega a `@claude-code-guide` con prompt estructurado (audit contra docs.anthropic.com/claude-code en VIVO, no memoria).
3. Persiste el report en `~/.claude/state/claude-config-audit/<YYYY-MM-DD>.md`.
4. Si encuentra **BLOCKER**, escribe la flag `~/.claude/state/claude-config-audit-blocker.flag` que un PreToolUse hook usa para bloquear edits a `settings.json` y `hooks/**` hasta resolución manual.
5. Append a `~/.claude/logs/claude-config-audit.jsonl` con timestamp + path + acción.

## Implementación

```bash
bash "${CLAUDE_PROJECT_DIR}/skills/claude-config-audit/run.sh" "$@"
```

## Cuándo correrlo

- **Cron lunes 7AM**: automático — feed al `morning-briefing`.
- **Manual**: tras `claude` upgrade, antes de cycle close, o si ⟦ user_name ⟧ sospecha drift upstream.
- **Triggered por bug**: si ARCA caza un hook fail con file-not-found o un skill que no encuentra state, correr `/claude-config-audit` ANTES del fix manual.

## Output esperado

Tabla resumen + detalle por item, agrupado por severidad: `BLOCKER` / `SERIOUS` / `MINOR` / `OK`. Hard cap 1500 palabras.
