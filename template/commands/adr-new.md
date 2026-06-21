---
description: Crea un Architecture Decision Record numerado (Nygard-lite) en docs/adr/. Usar tras decision arquitectural firme o cuando el hook auto-adr-detector lance el aviso [AUTO-ADR ADVISOR].
allowed-tools: Bash(bash*)
---

`$ARGUMENTS` es el titulo del ADR. Mismo flujo que `skills/adr-new/SKILL.md` — ese fichero es la fuente unica de verdad. Este markdown lo expone como slash command para invocacion directa por ⟦ user_name ⟧.

## Uso

```
/adr-new <titulo corto>
```

Ejemplos:

- `/adr-new langgraph-state-checkpointing`
- `/adr-new abandon-redis-for-sqlite-cache`
- `/adr-new chief-architect-blocking-gate`

## Proceso

Toda la logica vive en `skills/adr-new/run.sh` — fuente unica de verdad. El bash block captura `$ARGUMENTS` con un heredoc cuyo delimitador esta entre comillas simples (`<<'ARCA_ADR_NEW_EOF'`): bash garantiza zero-expansion en el cuerpo, asi que `$(...)`, backticks o `${VAR}` aterrizan como texto literal en `TITLE_RAW`. Pasarlo despues como argv `$1` a `run.sh` cierra el flujo dentro del unico script auditado. El patron canonico es ADR-007 (ARCA-SEC-1).

Cycle 4 (ARCA-SEC-1 B1): el heredoc neutraliza `$()` y backticks en payloads de una linea, pero un payload multi-linea puede inyectar el delimitador `ARCA_ADR_NEW_EOF` en su propia linea, cerrar el heredoc, y dejar el resto como codigo bash ejecutable. Como `/adr-new` solo acepta titulos en una linea de todas formas, rechazamos input multi-linea antes de invocar `run.sh`.

```bash
TITLE_RAW=$(cat <<'ARCA_ADR_NEW_EOF'
$ARGUMENTS
ARCA_ADR_NEW_EOF
)
# Heredoc appends a trailing newline; strip it so titles round-trip exactly.
TITLE_RAW="${TITLE_RAW%$'\n'}"

# Reject multi-line: any embedded newline = potential heredoc-terminator injection (ARCA-SEC-1 B1).
case "$TITLE_RAW" in
  *$'\n'*)
    echo "[/adr-new] ENTORNO: titulo multi-linea no permitido (ARCA-SEC-1 B1)." >&2
    echo "  /adr-new acepta solo titulos en una linea (sin saltos de linea)." >&2
    exit 2
    ;;
esac

bash "${CLAUDE_PROJECT_DIR:-${PWD}}/skills/adr-new/run.sh" "$TITLE_RAW"
```

## Convenciones (extracto de `docs/adr/README.md`)

- Status values: `Proposed`, `Accepted`, `Deprecated`, `Superseded by ADR-XXX`.
- Append-only. NUNCA editar el campo `Decision` de un ADR Accepted; escribir uno nuevo que supersede.
- File naming: `NNN-slug.md` zero-padded a 3 digitos.

## Anti-patterns

- NO uses `/adr-new` para registrar TODOs, dudas, ideas no decididas. ADR es para decisiones firmes.
- NO uses `/adr-new` con titulo generico ("/adr-new architecture", "/adr-new database"). El slug debe identificar la decision concreta.
- NO edites un ADR Accepted para cambiar la `Decision`. Crea uno nuevo que lo supersede.
