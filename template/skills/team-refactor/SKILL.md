---
name: team-refactor
description: Team preset para refactors grandes — 3 teammates (inventario + plan + tests). Evita el patrón "refactor que rompe 5 cosas que nadie sabía". Invócame cuando ⟦ user_name ⟧ diga /team-refactor, refactor grande, extract common logic, migrar patrón X a Y, o similar.
when_to_use: refactors que tocan >5 archivos o cambian contratos públicos (APIs, schemas, funciones exportadas)
argument-hint: <qué-refactorizar> + <qué-queda-igual-que-es-el-invariante>
disable-model-invocation: false
user-invocable: true
allowed-tools: Read Grep Glob Bash(git grep *) Bash(git log *)
model: opus
effort: high
---

# /team-refactor — refactor seguro 3 perspectivas

⟦ user_name ⟧ pidió refactor: `$ARGUMENTS`

3 teammates previenen el patrón típico: "refactor bonito que rompe call sites que nadie sabía que existían".

## Preflight

1. Si `$ARGUMENTS` no tiene **invariante explícita** ("después del refactor, X sigue funcionando igual") → aborta, pide a ⟦ user_name ⟧ definirla. Sin invariante, no hay criterio de éxito.
2. Si el scope es >10 archivos → avisa upfront: este refactor debería dividirse en 2-3 PRs independientes.
3. Si el refactor toca contrato público (funciones exportadas, schemas API, migrations DB) → sube el rigor, añade un 4º teammate de compat.

## Team (3 teammates)

| Teammate | Agent | Rol |
|---|---|---|
| **inventory** | `debt-detector` + skill `testing` | enumera TODOS los call sites del código a refactorizar (git grep), identifica code dead vs vivo, lista contratos públicos expuestos |
| **planner** | `chief-architect` | diseña el refactor en pasos atómicos (cada paso commit-able sin romper tests), detecta el "big-bang risk" y lo rompe |
| **test-guard** | `tester` | verifica que haya test suite que cubra el invariante ANTES de tocar nada, añade tests si faltan |

## Flujo

### Round 1 — inventory primero (NO paralelo)

El planner y el test-guard necesitan saber qué tocan. Inventory va solo primero:
- Lista de call sites con `file:line`
- Clasificación: alive (usado en >0 tests o main), dead (0 refs fuera del target), público (API/CLI), interno
- Diff estimado: aproximación de líneas a tocar

### Round 2 — planner + test-guard paralelo

Con el inventory en mano:
- **planner** propone sequence de N pasos. Cada paso debe ser:
  - atómico (1 commit)
  - reversible (revert limpio)
  - tests verdes AL FINAL del paso
- **test-guard** audita si cada paso del planner tiene tests que validen el invariante. Si falta cobertura → propone tests a añadir ANTES de ese paso.

### Round 3 — cross + dry-run

Lead aplica el planner paso 1 (sin commit) y corre tests:
- Si verde → plan viable, commit paso 1 y seguir.
- Si rojo → planner ajusta con el output del test-guard, otra iteración.

## Output

```markdown
## /team-refactor — {target}

### Invariante (⟦ user_name ⟧ dijo)
> {lo que debe seguir igual}

### Inventory
- call sites alive: {N} en {M} archivos
- call sites dead: {N} (candidatos para delete directo)
- contratos públicos afectados: {list}

### Plan (N pasos atómicos)
1. [prep] añadir tests faltantes para invariante (cobertura actual 45% → 85%)
2. [step 1] extraer función X a módulo Y — 1 commit, tests verdes
3. [step 2] ...
N. [cleanup] eliminar código dead identificado en inventory

### Riesgos
- paso K toca contrato público {f()} — reviewers sugeridos antes merge: {agent}
- posible regresión en módulo Z — cobertura baja, confianza media

### Go/No-go
- **GO** si todos los pasos tienen tests + invariante medible.
- **NO-GO** si hay <80% cobertura del invariante — añadir tests primero.
```

## Reglas duras

- **No hacer refactor sin tests que cubran el invariante**. Si hay que escribir tests primero, ese es el paso 1.
- **No agrupar 2 refactors en un plan**. "Refactor A + renombrar B" = 2 planes separados.
- **No aprobar plan con paso "big bang"**. Cada paso debe ser verdes-tests-al-final. Si hay un paso que rompe tests por diseño, la división está mal.
- **Deletear dead code explícitamente**. Si inventory marcó funciones dead, el cleanup del final las elimina — no las deja como "por si acaso".

**ultrathink** al definir los pasos atómicos. El error típico es pasos demasiado grandes ("migra todo el módulo") que luego no se pueden revertir sin perder 2 días.
