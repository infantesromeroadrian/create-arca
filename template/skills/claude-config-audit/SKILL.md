---
name: claude-config-audit
description: Auditoría exhaustiva semanal de la config de Claude Code (settings.json, hooks, skills, commands) contra la documentación oficial de Anthropic. Detecta drift, campos undocumented, env vars que dejaron de exportarse, schemas de hooks que mutaron upstream. Output estructurado por severidad con fix recomendado para cada hallazgo. Invocar en cron lunes 7AM (junto a morning-briefing y guardian-audit) o manualmente via /claude-config-audit cuando un bug huele a runtime drift.
---

# claude-config-audit

## Objetivo

Cerrar la clase de bugs "Claude Code cambió algo upstream y nuestra config quedó stale" sin esperar a que el bug se manifieste. Anthropic publica releases frecuentes con cambios silenciosos (env vars que dejan de exportarse, fields nuevos, schemas que mutan); ARCA tiene 29 hooks + 96 skills + 49 agentes acoplados al runtime — superficie demasiado grande para auditarla a ojo.

## Cuándo invocar

- **Scheduled (recomendado)**: lunes 7AM via cron — ver schedule registrado al cierre del bundle.
- **Manual on-demand**: tras un upgrade del CLI `claude`, antes de un cycle close, o cuando un bug huele a runtime drift.
- **Triggered por bug**: si ARCA caza un bug del tipo "hook X falla con file-not-found" o "skill Y no encuentra state", correr este audit ANTES del fix manual para confirmar/descartar drift sistémico.

## Whitelist de falsos positivos

**ANTES de clasificar cualquier finding como drift, consulta `docs/audit-policy.md`.** Ese archivo cataloga patrones que parecen drift pero son intencionales o factualmente correctos (red-team targets externos legítimos, refs a tokenizers de OpenAI, rankings factuales de capability, neutralidad de framework docs). Sin la whitelist, cada audit cycle re-flagea los mismos falsos positivos.

Si encuentras un patrón flagged + listado en `audit-policy.md` → clasifica `INTENTIONAL`, no drift. Si encuentras drift real no cubierto por la whitelist → flagealo + propón añadirlo a la whitelist si es la primera vez.

## Qué audita

20 puntos estructurados, agrupados en 6 categorías:

### A. Hooks payload + env vars

1. Schema completo del JSON stdin de cada evento (PreToolUse, PostToolUse, Stop, UserPromptSubmit, SessionStart, PreCompact, TaskCreated, TeammateIdle, etc.)
2. Variables de entorno que el runtime exporta a hooks (lista cerrada con docs oficiales)
3. Existencia y semántica actual de `CLAUDE_SESSION_ID`
4. Interpolación de `$HOME`, `$CLAUDE_PROJECT_DIR`, `$USER` en el campo `command`
5. Resolución de `$CLAUDE_PROJECT_DIR` cuando un hook vive en `~/.claude/settings.json` global

### B. Skills + slash commands env

6. Env vars que hereda un script de skill ejecutado vía slash command
7. Canal recomendado para que un skill conozca el `session_id` activo
8. Relación entre `CLAUDE_PROJECT_DIR` y el cwd de un skill

### C. Subagents / Agent Teams

9. Scoping de `session_id` en subagents (Task tool) y teammates (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`)
10. Si los hooks que disparan dentro de un subagent ven el id del subagent o del lead
11. Campo del payload o env var que distinga lead vs subagent vs teammate

### D. State sharing entre hooks/skills

12. Patrón oficial recomendado para compartir state entre hook y skill
13. Storage runtime que el cliente mantiene al día (`~/.claude/state/`, `~/.claude/sessions/<id>.json`, etc.)

### E. Worktrees + multi-proceso

14. Comportamiento de session_id con múltiples instancias `claude` corriendo
15. Coordinación o aislamiento entre instancias
16. Scope de `CLAUDE_PROJECT_DIR` por-instancia vs global

### F. Patrones que ARCA podría estar usando mal

17. `Bash(*)` blanket allow — práctica documentada vs anti-pattern
18. Sintaxis de matchers de hooks (regex vs glob vs substring) — schema formal
19. Campo `if:` en PreToolUse — sintaxis válida
20. Hook `type: "prompt"` con campo `model:` — API documentada o accidental

## Cómo invoca

El runner delega a `@claude-code-guide` con un prompt estructurado idéntico al que se usó manualmente el 2026-05-01. Le pide:
- Leer docs.anthropic.com/claude-code en VIVO (Brave/WebFetch/context7), no asumir memoria
- Por cada item devolver formato estructurado: `[ITEM N] DRIFT/BUG/MALUSO`, evidencia oficial, cómo lo usa ARCA, severidad, fix recomendado
- Hard cap 1500 palabras

## Output

Report markdown en `~/.claude/state/claude-config-audit/<YYYY-MM-DD>.md` con:
- Header (fecha, version del CLI, último commit auditado)
- Tabla resumen de severidades (BLOCKER / SERIOUS / MINOR / OK)
- Detalle por item
- Lista de acciones recomendadas ordenadas

Resumen condensado se inyecta en el siguiente `/morning-briefing` del lunes vía hook.

## Acciones automáticas

- Si detecta **BLOCKER** → escribe flag `~/.claude/state/claude-config-audit-blocker.flag` que un PreToolUse Bash hook lee para bloquear commits a `settings.json` y `hooks/**` hasta resolución manual.
- Si detecta **SERIOUS** → log a `~/.claude/logs/claude-config-audit.jsonl` + notificación en briefing.
- Si todo OK → log `{"audit":"clean", "ts":"..."}` y nada más.

## Histórico relevante

- **2026-05-01**: primer audit manual. Detectó 6 items (1 BLOCKER + 2 SERIOUS + 2 MINOR + 1 OK). Los 4 accionables se arreglaron en commits `a9d1a5b` y `54c74cc`.
