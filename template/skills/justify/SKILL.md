---
name: justify
description: Registra una justificacion textual para el siguiente Edit/Write/MultiEdit grande o critico (>=30 LOC en agents/, hooks/, commands/, settings.json, CLAUDE.md, .github/workflows/). El hook forced-justification.sh la consume y la valida via Ollama LLM-as-judge antes de permitir el cambio.
when_to_use: antes de un cambio grande (>=30 LOC) o un cambio en path critico — el hook bloqueara el Edit/Write/MultiEdit hasta que registres la justificacion. Llama esta skill cuando ARCA detecte que vas a tocar paths sensibles o cuando explicitamente quieras dejar trazabilidad de la decision.
argument-hint: <texto explicando que vas a cambiar y por que — UNA sola linea>
disable-model-invocation: false
user-invocable: true
allowed-tools: Bash
model: opus
effort: low
---

# /justify — Forced-justification gate (ARCA-SEC-1)

Hard gate de calidad que obliga a explicar el "por que" antes de cualquier cambio significativo. La justificacion se valida con un juez LLM local (Ollama Qwen 2.5 7B) que rechaza textos genericos ("fix bug", "refactor") y aprueba los que demuestran comprension del cambio.

## Cuando usarlo

- Estas a punto de hacer Edit/Write/MultiEdit con >= 30 LOC modificadas.
- El path tocado es critico: `agents/**`, `hooks/**`, `commands/**`, `settings.json`, `CLAUDE.md`, `.github/workflows/**`.
- Quieres dejar trazabilidad explicita aunque el cambio sea pequeno.
- El hook `forced-justification.sh` (PreToolUse:Edit/Write/MultiEdit) emitio `BLOCKED by ARCA Forced Justification gate` — debes lanzar `/justify` antes del retry.

## Cuando NO usarlo

- Cambios triviales en paths no criticos (< 30 LOC). El hook no se dispara y forzar `/justify` solo anade ruido.
- Cambios mecanicos masivos donde la "razon" es la misma para 50 archivos (rename, format-only). Para esos, mejor `BYPASS_JUSTIFICATION=1` con `BYPASS_REASON` documentado en `~/.claude/state/justification-bypasses.log`.
- Read/research operations — el hook solo dispara en escrituras.

## Como funciona

1. **Captura segura del texto.** El bloque bash en `commands/justify.md` envuelve `$ARGUMENTS` en un heredoc con delimitador entre comillas simples (`<<'ARCA_JUSTIFY_RAW_EOF'`). Bash no expande `$(...)`, backticks ni `$VAR` dentro. ARCA-SEC-1 hardening — ver ADR-007.
2. **Guard multilinea.** Un `case $TEXTO in *$'\n'*) exit 2 ;; esac` rechaza inputs multilinea antes de tocar `run.sh`. Cierra el vector residual donde el delimitador del heredoc aparezca dentro del payload.
3. **Persistencia per-PID.** `run.sh` invoca `hooks/lib/claude-process-id.sh` para obtener el PID del proceso `claude` ancestro. El state file vive en `~/.claude/state/current-justification-<claude_pid>.json` para que multiples sesiones concurrentes (worktrees, terminales paralelas) no colisionen. Ver Known Limitations en `CLAUDE.md`.
4. **Validacion LLM.** El proximo Edit/Write/MultiEdit que cumpla los triggers consume el state file. `forced-justification.sh` invoca `hooks/lib/llm-judge.sh` que llama Ollama con un prompt que valida coherencia entre la justificacion y el contenido del cambio. Veredictos: APPROVED, INCOHERENT, TOO_SHALLOW, TIMEOUT.
5. **TTL 120 segundos.** La justificacion expira tras 120s. Tiempo suficiente para que el agente lea contexto, ejecute 2-3 sub-tools, y proceda al Edit. Si caduca, el hook bloquea y pide una nueva.

## Anti-patterns

- **NO** uses `/justify` con texto generico tipo "fix bug" o "refactor". El juez Ollama dira `incoherent` y bloquea.
- **NO** uses `/justify` para edits triviales en paths no criticos. El hook no dispara, el comando es no-op semantico.
- **NO** acumules justificaciones encadenadas para un cambio multifile. Una `/justify` cubre el siguiente Edit. Para cambios compuestos, lanza `/justify` antes de cada Edit.
- **NO** modifiques el patron heredoc en `commands/justify.md`. Cada variante (sin comillas en delimitador, sin guard multilinea, con `TEXT="$ARGUMENTS"`) restablece una variante distinta del vector ARCA-SEC-1.

## Bypass (logged)

Para emergencias o cambios mecanicos masivos:

```bash
export BYPASS_JUSTIFICATION=1
export BYPASS_REASON="rename masivo X -> Y, 50 archivos"
```

Cada bypass se registra en `~/.claude/state/justification-bypasses.log` con timestamp ISO + path + razon. La auditoria semanal (`/guardian-audit`) revisa esta lista.

## Stats

`~/.claude/state/justification-stats.json` registra: blocked (gate disparado), approved_by_judge, rejected_by_judge_incoherent, rejected_by_judge_shallow, judge_timeout, bypass. Inspeccionar:

```bash
jq . ~/.claude/state/justification-stats.json
```

Feed para `/morning-briefing` y `/guardian-audit`.

## Cross-references

- **ADR-007** — Slash command `$ARGUMENTS` hardening (ARCA-SEC-1). Explica el vector y la mitigacion heredoc + case-newline.
- **ADR-006** — Auto-ADR feature (E.2). Sister skill `/adr-new` que tambien usa el patron ARCA-SEC-1.
- **ADR-009** — Hybrid LLM judge (Opus 4.8 + Qwen 7B). El juez del hot-path (forced-justification) es Qwen via Ollama; el juez de high-stakes (PR review, ADR completeness) es Opus via SDK.
- **`hooks/forced-justification.sh`** — el consumidor del state file.
- **`hooks/lib/llm-judge.sh`** — el invocador del juez Ollama con random-fence prompt-injection guard.
- **`hooks/lib/claude-process-id.sh`** — derive el PID del ancestro `claude` para per-process state isolation.
- **`commands/justify.md`** — el slash command user-facing que envuelve `run.sh`.

## Known limitations

- **Inverted-assertion canary T7b** — `tests/test_justify_hardening.sh` contiene un test que PASA cuando un bypass conocido del heredoc (atacante con read access a `commands/justify.md` que inyecta el delimitador inner) sigue funcionando. Documentado en ADR-007. Cierra solo cuando ARCA-SEC-2 migre `/justify` a un MCP tool (input via API estructurada, no shell parser).
