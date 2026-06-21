---
name: adr-new
description: Crea un Architecture Decision Record nuevo, numerado secuencialmente, con plantilla Nygard estandar (Status / Date / Deciders / Context / Decision / Rationale / Consequences). Invocame cuando ⟦ user_name ⟧ diga /adr-new <titulo>, escribe un ADR, documenta esta decision, o cuando @architect-ai acabe de proponer una decision arquitectural sin ADR.
when_to_use: tras una decision arquitectural firme — eleccion de framework, patron que cruza el ecosistema, tradeoff no obvio, supersession de un ADR previo
argument-hint: <titulo corto en kebab-case o lenguaje natural>
disable-model-invocation: false
user-invocable: true
allowed-tools: Bash
model: sonnet
effort: medium
---

# /adr-new — Auto-ADR (E.2)

Cierra el pecado mortal #4 de ARCA ("Arquitectura sin ADR / sin justificacion") generando el archivo numerado, dejando las 6 secciones Nygard listas para rellenar.

## Cuando usarlo

- `@architect-ai` propuso una decision arquitectural y el hook `auto-adr-detector.sh` emitio el aviso `[AUTO-ADR ADVISOR]`.
- ⟦ user_name ⟧ decide locking-in de un framework, DB, modelo, patron de despliegue.
- Una decision previa queda obsoleta — esta ADR supersede a la anterior.
- Quien lo lea en 6 meses no entendera el codigo sin ver el razonamiento.

## Cuando NO usarlo

- Eleccion bien entendida en la industria (`pytest` para tests Python).
- Decision efimera (nombre de rama de feature).
- El razonamiento ya cabe en un comentario sobre una funcion.

Ver `docs/adr/README.md` seccion "When to write an ADR".

## Flujo

1. Validar `$ARGUMENTS`: no vacio, longitud >= 5 chars utiles tras trim.
2. Sanitizar el slug:
   - lowercase
   - reemplazar todo lo que no sea `[a-z0-9]` por `-`
   - colapsar `-` repetidos
   - strip leading/trailing `-`
   - si tras sanitizacion queda vacio → abortar pidiendo titulo concreto
3. Escanear `docs/adr/[0-9][0-9][0-9]-*.md` y obtener `next_n = max(NNN) + 1`.
4. Bloquear con `flock` sobre `docs/adr/.adr-numbering.lock` para evitar carrera con otra invocacion paralela.
5. Renderizar `skills/adr-new/template.md` sustituyendo:
   - `{{NNN}}` por `next_n` zero-padded a 3 digitos
   - `{{TITLE}}` por el titulo limpio (minuscula, palabras separadas por espacios)
   - `{{DATE}}` por `date -I`
6. Escribir `docs/adr/NNN-slug.md`. Si ya existe, abortar (no sobrescribir).
7. Registrar en stats: `bash hooks/lib/auto-adr-stats.sh drafted_via_skill`.
8. Avisar a ⟦ user_name ⟧ del path creado y recordarle:
   - rellenar las 4 secciones de prosa
   - actualizar `docs/adr/README.md` indice
   - opcionalmente correr `bash hooks/lib/adr-judge.sh docs/adr/<NNN>-<slug>.md` antes de commit
   - declarar `/justify` antes del Edit que rellena las secciones (paths bajo `docs/**` no estan en la lista critica del gate, pero `/justify` documenta la intencion).

## Invocacion

Toda la logica ejecutable vive en `skills/adr-new/run.sh`. El skill y el slash command (`commands/adr-new.md`) son punteros al mismo script — asi no se duplica la sanitizacion del slug, el `flock` ni el render del template. El bash block usa el patron canonico ADR-007 (ARCA-SEC-1): heredoc con delimitador entre comillas simples, que prohibe a bash expandir `$(...)`, backticks o variables dentro del cuerpo. El payload aterriza como texto literal en `TITLE_RAW`, y de ahi pasa como argv `$1` a `run.sh`.

Cycle 4 (ARCA-SEC-1 B1): el heredoc neutraliza `$()` y backticks en payloads de una linea, pero un payload multi-linea puede inyectar el delimitador `ARCA_ADR_NEW_EOF` en su propia linea, cerrar el heredoc, y dejar el resto como codigo bash ejecutable. Como `/adr-new` solo acepta titulos en una linea, rechazamos input multi-linea antes de invocar `run.sh`.

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

Por que heredoc y no `"$ARGUMENTS"` directo: la doble comilla NO impide la expansion de `$(...)` cuando bash parsea la linea — solo desactiva word-splitting y globbing. Con un payload del tipo `x-$(touch /tmp/PWN)-y` el `$()` se ejecuta antes de que `run.sh` reciba el argv. Heredoc con delimitador `'ARCA_..._EOF'` es la unica forma documentada en bash de neutralizar ese vector — pero requiere que el body sea de una unica linea, de ahi el guard `case`.

## Sanity checks que hace el bloque

- Slug no vacio tras sanitizacion.
- `docs/adr/` existe (sino el proyecto no esta inicializado para ADRs).
- Plantilla existe.
- Lock para serializar numeracion bajo carga.
- No sobrescribe.
- Stats incrementadas tras exito.

## Edge cases conocidos

- Numeracion no contigua (001, 003, 005) → toma `max + 1 = 6`. Los huecos no se rellenan; renombrar ADRs rompe links externos.
- Si dos `/adr-new` corren a la vez, el `flock` serializa: el primero crea NNN, el segundo crea NNN+1.
- Slug colision (mismo NNN-slug) → abort. NUNCA sobrescribir.
- `$ARGUMENTS` con caracteres unicode → la sanitizacion los descarta. Si todo el titulo es unicode (raro, pero posible), abort por slug vacio.

## Stats

`~/.claude/state/auto-adr-stats.json` se actualiza:

| bucket | cuando |
|---|---|
| `detected` | hook `auto-adr-detector.sh` disparo nudge |
| `suppressed_dup` | hook detecto pero rate-limit lo silencio |
| `drafted_via_skill` | `/adr-new` creo un fichero |
| `judge_pass` | `hooks/lib/adr-judge.sh` lo aprobo |
| `judge_fail` | `hooks/lib/adr-judge.sh` encontro secciones vacias |
| `bypass` | operador exporto `ARCA_AUTO_ADR_BYPASS=1` |

Inspeccionar:

```bash
jq . ~/.claude/state/auto-adr-stats.json
```
