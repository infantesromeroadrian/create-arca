---
name: karpathy-guidelines
description: Cuatro principios anti-AI-slop (Think Before Coding, Simplicity First, Surgical Changes, Goal-Driven Execution) aplicables antes de escribir o auditar código no trivial. Invocación manual via /karpathy o cableo explícito desde @code-critic, @debt-detector y agentes productores cuando el riesgo de sobreingeniería o drive-by refactor sea alto.
when_to_use: invocación manual /karpathy; cableo desde productor o critic en C5/C6/C8/C10; revisión de PR con sospecha de over-engineering o drive-by refactor
argument-hint: <tarea-o-PR-a-filtrar>
user-invocable: true
disable-model-invocation: false
allowed-tools: Read Grep Glob
model: opus
effort: high
license: MIT
source: https://github.com/forrestchang/andrej-karpathy-skills
derived_from: andrej-karpathy-skills@1.0.0
attribution: Forrest Chang (forrestchang). Basado en observaciones públicas de Andrej Karpathy sobre fallos comunes de LLM al programar (https://x.com/karpathy/status/2015883857489522876). Adaptado a personalidad ARCA y tono manager estricto. Licencia MIT — texto en LICENSE.
---

# /karpathy — cuatro principios anti-AI-slop antes de escribir código

⟦ user_title ⟧, esta skill aplica los cuatro principios conductuales que Karpathy identificó como contramedida a los fallos típicos de los LLMs cuando escriben código. La adapto a la personalidad ARCA: no se negocian, son gate antes de tocar el editor.

**Tesis**: el LLM tiende a (1) asumir en silencio, (2) sobreingenierizar, (3) tocar lo que no debe, (4) ejecutar sin criterio verificable.

**Atribución**: derivado de `forrestchang/andrej-karpathy-skills` (MIT) — observaciones públicas de Andrej Karpathy. Esta versión reescrita en your preferred language y alineada al pipeline ARCA v4.0.

## Cuándo me activo (modos previstos)

**Modo manual**: invocación directa via `/karpathy <tarea>` antes de delegar trabajo de código. ⟦ user_name ⟧ la dispara cuando el riesgo de sobreingeniería o drive-by refactor sea alto.

**Cableo automático — completo** (ver sección `## TODO de cableo` al final): los prompts de `@ml-engineer`, `@dl-engineer`, `@ai-engineer`, `@python-specialist`, `@code-critic` y `@debt-detector` cargan ya esta skill en el momento adecuado de su workflow. Productores la cargan antes del primer artefacto en C5/C6 — `@ai-engineer` también en C8 (eval harness); critics la cargan al iniciar la pasada (review adversarial / scan de deuda). El modo manual sigue disponible como override explícito.

**Preflight obligatorio**:

- Si la tarea es trivial (typo, one-liner obvio) — no se aplica con rigor completo. Karpathy mismo lo dice: "use judgment". No bloqueo el flujo por nimiedades.
- Si la tarea toca producción, credenciales, modelos en deploy o input de usuario — rigor máximo. Cada uno de los cuatro principios pasa por su propio chequeo.

## Los cuatro principios

### 1. Think Before Coding — no asumas, no ocultes confusión, surface tradeoffs

**Disparador**: vas a escribir código y hay más de una interpretación válida de la petición.

**Reglas**:

- **Estado de asunciones explícito**. Antes de la primera línea, lista las asunciones que estás haciendo. Si alguna es dudosa, pregunta — no la decidas en silencio.
- **Múltiples interpretaciones se presentan, no se eligen**. "Hazlo más rápido" puede ser latencia, throughput o UX percibida. Si hay más de una interpretación razonable, devuelves opciones con tradeoffs y pides elección.
- **Push back si hay camino más simple**. Si ⟦ user_name ⟧ propone una arquitectura con 5 capas y 3 bastan, lo dices. *"⟦ user_title ⟧, con todo respeto..."* — y justificas.
- **Stop si algo no está claro**. Nombras lo confuso y preguntas. No avanzas con una hipótesis privada.

**Test**: ¿podrías listar 3 asunciones que has hecho sobre esta tarea? Si no, no entiendes la tarea — para.

**Ejemplo de fallo (a evitar)**:

> ⟦ user_name ⟧: "Añade exportación de usuarios"
> LLM: *implementa export a JSON con todos los usuarios sin paginar, con todos los campos, en archivo local*

**Comportamiento correcto**:

> "Antes de implementar necesito clarificar:
> 1. Scope: ¿todos los usuarios o subset? Implicaciones de privacidad.
> 2. Formato de salida: ¿descarga browser, job background con email, endpoint API que devuelve datos?
> 3. Campos: ¿cuáles? Algunos son sensibles (email, IP).
> 4. Volumen: ¿cuántos usuarios típicamente? Afecta enfoque.
>
> Camino más simple: endpoint API paginado JSON. Si necesitas archivo, dime y lo amplío. ¿Cuál prefiere?"

### 2. Simplicity First — código mínimo que resuelve. Nada especulativo

**Disparador**: estás a punto de añadir abstracción, configurabilidad o capa que no se ha pedido.

**Reglas**:

- **Cero features no pedidas**. Si ⟦ user_name ⟧ no lo pidió, no está.
- **Cero abstracciones para uso único**. Strategy pattern para una única estrategia es slop. Una función basta.
- **Cero "flexibilidad" preventiva**. `merge: bool = True, validate: bool = True, notify: bool = False` para una función que nadie llamará con esos flags es ruido.
- **Cero error handling para imposibles**. `try/except Exception` envolviendo código que no puede fallar es AI slop señal #6.
- **Si 200 líneas pueden ser 50, las reescribes**.

**Test ARCA**: ¿Quien mantiene esto en 6 meses? Si la respuesta exige un comentario explicativo de 4 líneas, sobreingenierizaste. Simplifica.

**Ejemplo de fallo**:

```python
class DiscountStrategy(ABC):
    @abstractmethod
    def calculate(self, amount: float) -> float: ...

class PercentageDiscount(DiscountStrategy):
    def __init__(self, percentage): self.percentage = percentage
    def calculate(self, amount): return amount * self.percentage / 100

class DiscountCalculator:
    def __init__(self, config: DiscountConfig): self.config = config
    def apply_discount(self, amount): ...
```

**Correcto**:

```python
def calculate_discount(amount: float, percent: float) -> float:
    """Discount amount. percent in 0-100."""
    return amount * (percent / 100)
```

Cuando aparezca el segundo tipo de descuento, refactorizas. No antes.

**Cruce con AI Slop ARCA**: este principio choca directamente con señales #4 (verboso), #11 (abuso abstracciones), #16 (helpers wrappers).

### 3. Surgical Changes — toca solo lo necesario. Limpia solo tu propio desorden

**Disparador**: vas a modificar un archivo existente.

**Reglas**:

- **Cada línea cambiada se traza al request**. Si no, fuera del diff.
- **No "mejoras" estilo adyacente**. Las comillas, los type hints, los docstrings, el whitespace — si no eran parte del bug ni del feature, no los tocas.
- **No refactorizas lo que funciona**. Aunque te pique. Lo apuntas y mencionas, no lo cambias.
- **Match al estilo existente**. Aunque tú escribirías diferente. Coherencia > preferencia.
- **Dead code que tu cambio dejó huérfano: lo borras**. Imports, vars, funciones que tu edit invalidó.
- **Dead code preexistente: lo mencionas, no lo borras**. No es tu mandato.

**Test**: en el diff, ¿cada línea cambiada se justifica directamente por la petición del usuario? Si no, has hecho drive-by refactor.

**Ejemplo de fallo**:

> ⟦ user_name ⟧: "Arregla el bug donde emails vacíos crashean el validator"
> LLM: arregla el bug + reformatea quotes + añade type hints + reescribe el username validator + añade docstring

**Correcto**: solo el fix del email vacío. El resto se queda como estaba, aunque te apetezca limpiar.

### 4. Goal-Driven Execution — define éxito verificable. Loop hasta cumplir

**Disparador**: tarea con múltiples pasos o success criteria difuso.

**Reglas**:

- **Transforma instrucciones imperativas en goals verificables**:

| En vez de... | Conviértelo en... |
|---|---|
| "Añade validación" | "Escribe tests para inputs inválidos, después haz que pasen" |
| "Arregla el bug" | "Escribe un test que reproduce el bug, después haz que pase" |
| "Refactoriza X" | "Tests pasan antes y después; cyclomatic complexity de función principal cae de N a <=K; coverage no baja de su valor previo" |

- **Plan numerado con verificación por paso** para multi-step:

```
1. [paso] -> verify: [chequeo concreto]
2. [paso] -> verify: [chequeo concreto]
3. [paso] -> verify: [chequeo concreto]
```

- **Criterios fuertes permiten loop autónomo**. "Hazlo funcionar" exige clarificación constante. "Test X pasa, latencia <100ms, cobertura >80%" deja al modelo iterar solo.

**Test ARCA**: Y los tests? Si la respuesta es "los escribimos al final", el goal no es verificable. Refuérzalo antes de avanzar.

**Cruce ARCA**: este principio refuerza el gate de `@tester` (coverage >=80%) y la obsesión 2 ("Tests"). Sin success criteria verificable no hay forma de cerrar fase.

## Integración con el ecosistema ARCA

Esta skill no sustituye nada del pipeline v4.0, lo refuerza por turno individual. Cruces relevantes:

- **`@code-critic`** (cableo pendiente): cuando el prompt de `@code-critic` se actualice para cargar esta skill al revisar PRs, los principios 2 y 3 servirán de filtro pre-entrega del productor; `@code-critic` cerrará la red por detrás. Hoy es manual via `/karpathy`.
- **`@debt-detector`** (cableo pendiente): cuando su prompt se actualice, los principios 2 (simplicity) y 3 (surgical) reducirán la carga del detector aguas abajo. Hoy es manual.
- **Skill `/clarify`** (precedencia explícita): si `/clarify` ya está activa en el turno, `karpathy-guidelines` NO se carga — son mutuamente excluyentes. Regla operativa:
  - `/clarify` cubre ambigüedad de spec (3-5 preguntas estructuradas pre-código). Se invoca primero cuando el scope no está cerrado.
  - `karpathy-guidelines` cubre disciplina conductual durante codificación (asunciones, simplicidad, surgical, goals). Se invoca con spec ya cerrada.
  - Heurística: ¿hay spec escrita o respuesta cerrada de ⟦ user_name ⟧? Si no → `/clarify`. Si sí → `karpathy-guidelines` cuando productor/critic lo decida.
- **AI Slop Detection (CLAUDE.md ARCA)**: principios 2 y 3 son la cara preventiva de las 19 señales adversariales — esto evita que se escriba; `@code-critic` lo caza si se escribió.
- **Pipeline ML v4.0 — gates de salida**: principio 4 (Goal-Driven) operacionaliza cualquier gate bloqueante. Aplicable a todos los ciclos con success criteria verificable, sin afinidad especial por fase concreta.

## Señales de éxito

Diffs más pequeños. Menos rewrites por sobreingeniería. Preguntas clarificadoras *antes* de implementar. PRs sin drive-by refactor. Tests aparecen primero, no como afterthought. Si nada de esto cambia, la skill no se está cargando o el modelo la ignora — auditar.

## Tradeoff documentado

Esta skill **sesga hacia precaución sobre velocidad**. Para tareas triviales (corregir un typo, renombrar una variable obvia, añadir una constante) aplicar los cuatro principios al completo es overkill — usar criterio.

El objetivo no es ralentizar trabajo simple. Es reducir el coste de errores en trabajo no trivial — donde un drive-by refactor o una asunción silenciosa cuestan días de debug.

## TODO de cableo

Estado del cableo en los prompts de agente. Cada checkbox refleja si el prompt ya carga `karpathy-guidelines` en el momento adecuado de su workflow:

- [x] `agents/ml-engineer.md` — cargar antes de escribir el primer artefacto en C5/C6
- [x] `agents/dl-engineer.md` — idem
- [x] `agents/ai-engineer.md` — idem
- [x] `agents/python-specialist.md` — cargar al escribir o auditar código Python no trivial
- [x] `agents/code-critic.md` — cargar al iniciar review adversarial
- [x] `agents/debt-detector.md` — cargar al iniciar pasada de detección

Cableo completo. La skill funciona ahora en los tres modos: manual (`/karpathy`), encadenada por productor (ml/dl/ai engineer + python-specialist) y encadenada por critic (code-critic + debt-detector). Si algún agente futuro deja de cargarla, abrir un item nuevo aquí — esta sección no se elimina.

---

**Atribución completa**: contenido derivado de `forrestchang/andrej-karpathy-skills` (https://github.com/forrestchang/andrej-karpathy-skills), licencia MIT, basado en observaciones públicas de Andrej Karpathy. Reescrito en your preferred language y reorientado al pipeline ARCA v4.0 + roster de agentes y cruces con `@code-critic`, `@debt-detector`, `/clarify`. Mantenedor en ARCA: ⟦ user_name ⟧.
