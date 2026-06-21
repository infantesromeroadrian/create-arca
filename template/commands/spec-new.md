---
description: Crea un Spec-Driven Development bundle (requirements + design + tasks + spec.lock.json) en docs/specs/<feature>/. Solo cuando los triggers ADR-027 R1-R4 disparan. Usar tras ADR firmado en C4 Design.
allowed-tools: Bash(bash*)
---

`$ARGUMENTS` son `<type> <feature-name>`. Mismo flujo que `skills/spec-new/SKILL.md` — ese fichero es la fuente unica de verdad. Este markdown lo expone como slash command para invocacion directa por ⟦ user_name ⟧.

## Uso

```
/spec-new <type> <feature-name>
```

`<type>` ∈ `{api, ml, rag, agent}`. `<feature-name>` kebab-case, min 5 chars utiles.

Ejemplos:

- `/spec-new api user-export-gdpr`
- `/spec-new ml fraud-detection-classifier-v2`
- `/spec-new rag legal-corpus-retrieval`
- `/spec-new agent customer-support-triage`

## Cuando usarlo (ADR-027 trigger matrix)

SOLO si CUALQUIERA dispara:

- **R1** Feature expone API contract (OpenAPI 3.1 / gRPC / MCP tool schema)
- **R2** Toca PII / GDPR Art 22 / EU AI Act high-risk / SOC 2 in-scope
- **R3** Integra ≥ 2 bounded contexts
- **R4** C10 deploy con rollback critico (RTO ≤ 5 min) AND user-facing

Si ninguno → fast-track ARCA, NO usar `/spec-new`.

## Cuando NO usarlo

- C2 EDA, C3 Hypothesis, C5 POC (anti-pattern, kills iteracion).
- Bug fix <50 LOC sin cambio contract.
- Refactor que preserva behaviour observable.
- HTB / red-team work.
- ANTES de tener ADR firmado.

## Proceso

Toda la logica vive en `~/.claude/skills/spec-new/run.sh` — fuente unica de verdad. El bash block captura `$ARGUMENTS` con el patron heredoc canonico (ADR-007 / ARCA-SEC-1 B1) que neutraliza `$()`, backticks y `${VAR}`. El payload aterriza como texto literal, se parte en 2 tokens (type + feature), y se pasan como argv `$1` y `$2` a `run.sh`.

Cycle 4 (ARCA-SEC-1 B1): rechazamos input multi-linea antes de invocar `run.sh` para impedir injection del delimitador heredoc.

```bash
ARGS_RAW=$(cat <<'ARCA_SPEC_NEW_EOF'
$ARGUMENTS
ARCA_SPEC_NEW_EOF
)
# Strip ONLY trailing newlines (heredoc residue). Embedded newlines stay
# so the rejection guard below can still trigger — silent truncation
# (greedy %%$'\n'*) was removed per ADR-028 B-4 fix because it turned the
# multi-line detector below into dead code (security theater).
while [[ "$ARGS_RAW" == *$'\n' ]]; do
    ARGS_RAW="${ARGS_RAW%$'\n'}"
done

# Reject any embedded newline — potential heredoc-terminator injection
# (ARCA-SEC-1 B1). Active again now that trailing-only strip preserves
# embedded newlines for this case to match.
case "$ARGS_RAW" in
  *$'\n'*)
    echo "[/spec-new] ENTORNO: argumentos multi-linea no permitidos (ARCA-SEC-1 B1)." >&2
    echo "  /spec-new acepta solo: <type> <feature-name> en una linea." >&2
    exit 2
    ;;
esac

# Split into exactly 2 fields (type + feature). Reject if !=2 tokens.
read -r SPEC_TYPE SPEC_FEATURE EXTRA <<< "$ARGS_RAW"

if [ -z "${SPEC_TYPE:-}" ] || [ -z "${SPEC_FEATURE:-}" ]; then
    echo "[/spec-new] ERROR: faltan argumentos." >&2
    echo "  Uso: /spec-new <type> <feature-name>" >&2
    echo "  type valido: api | ml | rag | agent" >&2
    exit 1
fi

if [ -n "${EXTRA:-}" ]; then
    echo "[/spec-new] ERROR: demasiados argumentos." >&2
    echo "  Uso: /spec-new <type> <feature-name>" >&2
    echo "  feature-name debe ser una sola palabra (kebab-case sin espacios)." >&2
    exit 1
fi

bash "${HOME}/.claude/skills/spec-new/run.sh" "$SPEC_TYPE" "$SPEC_FEATURE"
```

## Convenciones

- Bundle path: `docs/specs/<feature-slug>/`
- Append-only. NUNCA overwrite. Si necesitas regenerar: `rm -rf docs/specs/<slug>/` manual primero.
- `spec.lock.json` se regenera automaticamente al crear; rehash via S4 hook (entregable futuro).
- design.md DEBE linkear a un ADR (`docs/adr/NNN-*.md`). Si no hay ADR, crear primero con `/adr-new`.

## Anti-patterns

- NO uses `/spec-new` para tareas fast-track. Si dudas, no lo uses.
- NO dupliques contenido del ADR en design.md. Linkea con `[ADR-NNN](../../adr/NNN-slug.md)`.
- NO edites `spec.lock.json` a mano.
- NO crees specs con type generico ("misc", "general") — el type guia la plantilla y el drift hook.
