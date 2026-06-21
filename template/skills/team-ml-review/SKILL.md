---
name: team-ml-review
description: Team preset para review de trabajo ML/DL — 3 teammates (datos, matemática, producción). Invócame cuando ⟦ user_name ⟧ diga /team-ml-review, revisa este training, auditad este modelo, antes de deploy modelo, o similar.
when_to_use: review pre-deploy de modelo ML, antes de firmar C8 (Quality) del pipeline, cuando un experimento supera baseline y hay dudas si es real
argument-hint: <path-al-notebook/PR/modelo | id-experimento-mlflow>
disable-model-invocation: false
user-invocable: true
allowed-tools: Read Grep Glob Bash(git diff *) Bash(mlflow *)
model: opus
effort: xhigh
---

# /team-ml-review — review ML 3 perspectivas

⟦ user_name ⟧ pidió review ML sobre: `$ARGUMENTS`

3 teammates cubriendo data integrity / math correctness / production viability. Alineado con gates C2 (Data) + C6 (Build) + C8 (Quality) del pipeline ML v4.0.

## Preflight

1. Si el target es un PR ML/DL, confirmar que el diff incluye tests + métricas con IC, no solo el model.py.
2. Si el modelo supera baseline con margen sospechoso (>20%) → flag alto para data-auditor: posible leakage.

## Team (3 teammates con roles no solapados)

| Teammate | Agent | Enfoque |
|---|---|---|
| **data-auditor** | `data-validator` | leakage train/test, drift por subgrupo, duplicados cross-split, cobertura, balance de clases, temporal leakage |
| **math-auditor** | `math-critic` | loss function dimensions, gradients stability, optimizador + LR schedule, métricas con IC, statistical significance vs baseline, fairness across subgroups |
| **prod-auditor** | `chief-architect` + skill `inference-optimization` | latencia p95, memoria peak, quantización viable, drift en prod, plan de monitoring + rollback |

## Flujo

### Round 1 — paralelo (cada uno su eje)

Cada teammate produce un reporte de findings + veredicto en su eje (GO / GO-CON-CONDICIONES / BLOCK).

### Round 2 — cross adversarial

- **data-auditor** lee findings math: si math-critic dice "loss correcta", verifica que el test set no esté en training (leakage invalida cualquier loss buena).
- **math-auditor** lee findings data: si data-auditor flagea split mal hecho, re-evalúa métricas como "sin evidencia estadística".
- **prod-auditor** lee ambos: si hay leakage O math inestable → prod BLOCK automático, no hace sentido optimizar latencia de algo que no generaliza.

### Round 3 — veredicto del lead

Regla de agregación:

| data | math | prod | decisión |
|---|---|---|---|
| GO | GO | GO | APROBADO para C10 Deploy |
| GO | GO | GO-CON | APROBADO condicional (cumplir condiciones prod) |
| GO | GO-CON | * | devolver a @ml-engineer con findings math específicos |
| GO-CON | * | * | devolver a @data-engineer / @data-validator |
| BLOCK | * | * | REJECT — re-trabajar C2 (Data) |
| * | BLOCK | * | REJECT — re-trabajar C6 (Build) |
| * | * | BLOCK | REJECT — re-trabajar C8/C9/C10 |

## Output

```markdown
## /team-ml-review — {target}

### Data integrity (data-validator)
- veredicto: {GO | GO-CON | BLOCK}
- findings:
  - [leakage] <file/split>:<descripción>
  - [cobertura] subgrupo X con n=<bajo>
  - [temporal] <...>

### Math correctness (math-critic)
- veredicto: {…}
- findings:
  - [loss] <línea> — <problema>
  - [métrica] reportan X pero sin IC — no es significativo vs baseline
  - [gradient] <...>

### Production viability (chief-architect)
- veredicto: {…}
- latencia p95: <ms> vs SLA <ms>
- memoria peak: <MB>
- plan rollback: {existe | falta | incompleto}
- monitoring: drift alerts {configurado | no}

### Decisión final
- **{APROBADO | CONDICIONAL | REJECT}**
- próximo paso: {deploy C10 | arreglar findings X/Y/Z | re-train con datos corregidos}
```

## Reglas duras

- **No aprobar sin IC en métricas**. "94.2% accuracy" sin bootstrap IC o test estadístico vs baseline es prohibido.
- **No aprobar sin fairness por subgrupo**. Si el dataset tiene subgrupos (género, geo, tier), métricas globales no bastan.
- **No aprobar si latencia p95 > SLA**. Aunque la métrica sea buena — modelo inservible en prod.
- **Leakage tentativo = BLOCK**. No "flag para investigar después" — el valor del review es parar ANTES de deploy.

**ultrathink** en Round 2 cross. Las métricas están mal casi siempre por razones que cruzan ejes: un split temporal malo (data) hace que la loss reporte correcta (math) pero el modelo no generaliza (prod). Solo el cross detecta esto.
