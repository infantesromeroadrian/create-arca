---
name: ml-code-store-promote
description: Promote a function or class from `<proyecto>/src/` to the per-project `ml-code-store/` (ADR-026). Generates the migration diff, moves the symbol to the proper category, updates imports in the project, and seeds a unit test. ⟦ user_name ⟧ must approve the candidate before this skill runs — ⟦ user_name ⟧-aprobado entries live in `<proyecto>/ml-code-store-proposals.md`. Invoke as `/ml-code-store-promote <symbol>` after `@maintainability-engineer` emitted a STORE-CANDIDATE proposal that ⟦ user_name ⟧ marked APPROVED.
---

# ml-code-store-promote

## Objetivo

Cerrar el loop HITL del ml-code-store mandate (ADR-026). Cuando `@maintainability-engineer` emite un `STORE-CANDIDATE` y ⟦ user_name ⟧ lo marca APROBADO en `<proyecto>/ml-code-store-proposals.md`, esta skill ejecuta la migración mecánicamente: mueve la función al directorio correcto, actualiza los imports en `src/`, añade el símbolo a `__init__.py` del subpaquete del store y siembra un test unitario.

## Cuándo invocar

- **Manual**: `/ml-code-store-promote <symbol>` tras revisar `ml-code-store-proposals.md` y firmar APPROVED.
- **NO invocar** cuando:
  - El candidato tiene status PENDING o REJECTED.
  - El símbolo no es atómico (verifica los 3 criterios: atomicidad / reusabilidad / escalabilidad).
  - El proyecto no tiene `ml-code-store/` skeleton (en ese caso, primero `@project-planner` lo crea).

## Flow

1. **Localizar candidato** en `<proyecto>/ml-code-store-proposals.md` con status APPROVED.
2. **Identificar destino** (categoría granular en `ml-code-store/{ml,data,utils}/<sub>/`) — leer la propuesta del agent.
3. **Mover símbolo**: extraer la def/class del archivo origen, escribirla en el archivo destino (creando el `.py` si no existe), respetar imports y signatures.
4. **Actualizar `__init__.py`** del subpaquete con `from .<modulo> import <symbol>`.
5. **Reemplazar imports** en `src/` por `from ml_code_store.<categoria>.<sub>.<modulo> import <symbol>`.
6. **Sembrar test** en `ml-code-store/tests/<categoria>/<sub>/test_<modulo>.py` con un caso happy-path (⟦ user_name ⟧ añadirá edge cases manualmente).
7. **Marcar como MIGRATED** en `ml-code-store-proposals.md` con la fecha + commit hash.
8. **Re-correr `@code-critic` + `@maintainability-engineer`** sobre el cambio para cerrar el ciclo.

## Output

- Diff git con todos los cambios.
- Línea actualizada en `ml-code-store-proposals.md`:
  ```
  STORE-CANDIDATE-N — APPROVED 2026-MM-DD — MIGRATED 2026-MM-DD (commit <sha>)
  ```
- Test esqueleto en `ml-code-store/tests/...`.

## Anti-patterns

- **NO** promover símbolos privados (prefijo `_`) — son por contrato no estables.
- **NO** promover sin que ⟦ user_name ⟧ haya firmado APPROVED. Si dudas, vuelve a `@maintainability-engineer` y exige propuesta formal.
- **NO** mover lógica con dependencias del proyecto (configs hardcoded, paths absolutos del proyecto, lectura de `os.environ` ad-hoc) — refactoriza primero a forma genérica con DI explícito, luego propón.
- **NO** crear ramas paralelas en el store con la misma función bajo nombres distintos. Si la firma cambia, ADR + cambio explícito en el caller, no fork silencioso.

## Cross-references

- **ADR-026** — ml-code-store mandate per project.
- **`agents/maintainability-engineer.md` v1.2.0** — emite STORE-CANDIDATE / STORE-DUPLICATION / STORE-EXISTS-NOT-USED.
- **`agents/project-planner.md` v1.2.0** — crea el skeleton del store en C1.
- **`hooks/ml-code-store-duplication-detector.sh`** — advisory hook PostToolUse complementario.

## Estado actual

Skill documentada como SKILL.md. La automatización completa (`run.sh`) está deferred — por ahora la migración la ejecuta `@python-specialist` siguiendo este flow paso a paso. Cuando aparezca el primer batch de >5 promociones aprobadas en un mismo proyecto, vale la pena automatizar.
