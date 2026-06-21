---
name: langgraph
description: "LangGraph ADVANCED: Graph API, Functional API, checkpointing, human-in-the-loop, production patterns. Use for complex multi-agent workflows. For basics (StateGraph, nodes, edges), use langgraph-fundamentals instead."
globs:
  - "**/graph*.py"
  - "**/workflow*.py"
  - "**/langgraph*.py"
  - "**/state*.py"
effort: high
---

# LangGraph Best Practices 2025 (v1.x)

> **ARCA preference:** sustituir `init_chat_model("openai:gpt-4o")` por `init_chat_model("anthropic:claude-sonnet-4-6")` al portar a ARCA. Los ejemplos siguen el formato de la doc oficial de LangGraph v1 (`provider:model` con OpenAI como default upstream).

## Versiones Actuales (Enero 2025)

| Paquete | Versión |
|---------|---------|
| langgraph | 1.0.x |
| langgraph-checkpoint | 4.0.0 |
| langgraph-checkpoint-postgres | 3.0.3 |
| Python | 3.10+ |

## [WARN] CAMBIOS CRÍTICOS v1.0

```
┌─────────────────────────────────────────────────────────────────┐
│ ANTES (v0.x)                       │ AHORA (v1.x)              │
├─────────────────────────────────────────────────────────────────┤
│ langgraph.prebuilt.create_react_agent │ langchain.agents.create_agent │
│ LCEL vs LangGraph                  │ create_agent vs LangGraph │
│ Solo Graph API                     │ Graph API + Functional API │
│ interrupt_before=["node"]          │ interrupt() function      │
│ MemorySaver                        │ InMemorySaver             │
│ PostgresSaver(conn)                │ PostgresSaver.from_conn_string() │
└─────────────────────────────────────────────────────────────────┘
```

---

## Cuándo Usar create_agent vs LangGraph

| Caso de Uso | Herramienta |
|-------------|-------------|
| Agente simple con tools | `langchain.agents.create_agent` |
| RAG básico | `create_agent` + retriever tool |
| Control fino sobre agent loop | `create_agent` + middleware |
| Branching/condicionales complejos | **LangGraph** |
| Cycles/loops custom | **LangGraph** |
| Multi-agent orchestration | **LangGraph** |
| Human-in-the-loop granular | **LangGraph** |
| Long-running workflows | **LangGraph** |
| State persistence custom | **LangGraph** |
| Visualización de workflow | **LangGraph** (Graph API) |

### Regla 2025
```
create_agent para agentes estándar con middleware
LangGraph para workflows complejos y multi-agent
Functional API para integrar LangGraph en código existente
Graph API para control total y visualización
```

---

## Dos APIs Disponibles

### 1. Graph API (StateGraph)
- Control total sobre estructura del workflow
- Visualización del grafo
- State compartido entre nodes
- Time-travel debugging

### 2. Functional API (@entrypoint, @task) - NUEVO
- Integración con código existente
- Sin restructurar a DAG
- Menos boilerplate
- Mismo runtime que Graph API

```python
# Puedes mezclar ambas APIs en el mismo proyecto
from langgraph.graph import StateGraph
from langgraph.func import entrypoint, task
```

---

## Functional API (NUEVO en v1.0)

### Conceptos Básicos
```python
from langgraph.func import entrypoint, task
from langgraph.checkpoint.memory import InMemorySaver
from langgraph.types import interrupt

@task
def process_data(data: str) -> str:
    """Task: unidad discreta de trabajo."""
    return f"Processed: {data}"

@task
def analyze(text: str) -> dict:
    """Tasks se ejecutan async y se checkpointean."""
    return {"analysis": text, "score": 0.95}

@entrypoint(checkpointer=InMemorySaver())
def my_workflow(inputs: dict) -> dict:
    """Entrypoint: punto de entrada del workflow."""
    # Tasks retornan futures - usar .result() para obtener valor
    processed = process_data(inputs["data"]).result()
    analysis = analyze(processed).result()
    return analysis

# Ejecutar
config = {"configurable": {"thread_id": "user_123"}}
result = my_workflow.invoke({"data": "hello"}, config)
```

### Parallel Execution con Tasks
```python
@task
def fetch_from_api(endpoint: str) -> dict:
    """Simula llamada a API."""
    return {"endpoint": endpoint, "data": "..."}

@entrypoint(checkpointer=InMemorySaver())
def parallel_workflow(endpoints: list[str]) -> list[dict]:
    # Lanzar tasks en paralelo (retornan futures)
    futures = [fetch_from_api(ep) for ep in endpoints]
    
    # Esperar todos los resultados
    results = [f.result() for f in futures]
    return results

# Ejecuta todas las llamadas concurrentemente
result = parallel_workflow.invoke(
    ["/api/users", "/api/orders", "/api/products"],
    config
)
```

### Human-in-the-Loop con interrupt()
```python
from langgraph.types import interrupt, Command

@task
def generate_content(topic: str) -> str:
    """Genera contenido."""
    return f"Content about: {topic}"

@entrypoint(checkpointer=InMemorySaver())
def review_workflow(topic: str) -> dict:
    content = generate_content(topic).result()
    
    # PAUSA - espera input humano
    approval = interrupt({
        "content": content,
        "question": "Do you approve this content?",
        "options": ["approve", "reject", "edit"]
    })
    
    if approval == "approve":
        return {"status": "published", "content": content}
    elif approval == "reject":
        return {"status": "rejected"}
    else:
        # Podrías tener otro interrupt para edición
        return {"status": "needs_edit", "content": content}

# Primera ejecución - para en interrupt()
config = {"configurable": {"thread_id": "review_1"}}
result = review_workflow.invoke("AI trends", config)
# result contiene el payload del interrupt

# Después de revisión humana - resumir con Command
from langgraph.types import Command
result = review_workflow.invoke(
    Command(resume="approve"),  # Valor que recibe interrupt()
    config
)
```

### Previous State (Memoria entre invocaciones)
```python
@entrypoint(checkpointer=InMemorySaver())
def counter_workflow(increment: int, *, previous: int | None = None) -> int:
    """previous contiene el valor guardado de la invocación anterior."""
    current = (previous or 0) + increment
    
    # entrypoint.final permite retornar un valor diferente al que se guarda
    return entrypoint.final(
        value=current,      # Lo que retorna invoke()
        save=current        # Lo que se guarda para next previous
    )

config = {"configurable": {"thread_id": "counter_1"}}
counter_workflow.invoke(5, config)   # Returns 5
counter_workflow.invoke(3, config)   # Returns 8 (previous=5)
counter_workflow.invoke(2, config)   # Returns 10 (previous=8)
```

---

## Graph API (StateGraph)

### State - Definición

#### Con TypedDict (Recomendado)
```python
from typing import TypedDict, Annotated
from langgraph.graph.message import add_messages

class AgentState(TypedDict):
    messages: Annotated[list, add_messages]  # Con reducer
    current_step: str
    context: dict
    error: str | None
```

#### Reducers - Cómo Merge State Updates
```python
from typing import Annotated
from operator import add

class State(TypedDict):
    # add_messages: mergea listas de mensajes inteligentemente
    messages: Annotated[list, add_messages]
    
    # add: concatena listas
    steps: Annotated[list[str], add]
    
    # Sin reducer: último valor gana (overwrite)
    current_node: str
```

### Nodes - Definición
```python
from langchain.chat_models import init_chat_model

model = init_chat_model("openai:gpt-4o")

def chatbot_node(state: AgentState) -> dict:
    """Node que llama al LLM."""
    response = model.invoke(state["messages"])
    return {"messages": [response]}  # Solo retorna updates
```

### Edges - Conexiones
```python
from langgraph.graph import StateGraph, START, END

builder = StateGraph(AgentState)
builder.add_node("chatbot", chatbot_node)
builder.add_node("tools", tool_node)

# Edges fijos
builder.add_edge(START, "chatbot")
builder.add_edge("tools", "chatbot")  # Loop back
```

### Conditional Edges
```python
def should_continue(state: AgentState) -> str:
    """Decide siguiente node basado en state."""
    last_message = state["messages"][-1]
    
    if last_message.tool_calls:
        return "tools"
    return END

builder.add_conditional_edges(
    "chatbot",
    should_continue,
    {
        "tools": "tools",
        END: END
    }
)
```

### Compilación
```python
from langgraph.checkpoint.memory import InMemorySaver

# Con checkpointer (RECOMENDADO)
checkpointer = InMemorySaver()
graph = builder.compile(checkpointer=checkpointer)

# Ejecutar
config = {"configurable": {"thread_id": "user_123"}}
result = graph.invoke({"messages": [("user", "Hola")]}, config)
```

---

## Checkpointing - Persistencia

### InMemorySaver (Dev/Test)
```python
from langgraph.checkpoint.memory import InMemorySaver

checkpointer = InMemorySaver()
graph = builder.compile(checkpointer=checkpointer)
```

### PostgreSQL (Producción) - API Actualizada
```python
from langgraph.checkpoint.postgres import PostgresSaver

DB_URI = "postgresql://user:pass@host:5432/langgraph"

# NUEVO: usar from_conn_string (context manager)
with PostgresSaver.from_conn_string(DB_URI) as checkpointer:
    # IMPORTANTE: llamar setup() la primera vez
    checkpointer.setup()  # Crea tablas
    
    graph = builder.compile(checkpointer=checkpointer)
    result = graph.invoke(input, config)
```

### PostgreSQL con Connection Pool
```python
from langgraph.checkpoint.postgres import PostgresSaver
from psycopg_pool import ConnectionPool

DB_URI = "postgresql://user:pass@host:5432/langgraph"

# Pool para producción
pool = ConnectionPool(conninfo=DB_URI, max_size=10)

with pool.connection() as conn:
    checkpointer = PostgresSaver(conn)
    checkpointer.setup()
    
    graph = builder.compile(checkpointer=checkpointer)
```

### Async PostgreSQL
```python
from langgraph.checkpoint.postgres import AsyncPostgresSaver

async with AsyncPostgresSaver.from_conn_string(DB_URI) as checkpointer:
    await checkpointer.setup()
    graph = builder.compile(checkpointer=checkpointer)
    result = await graph.ainvoke(input, config)
```

---

## Human-in-the-Loop

### Graph API: interrupt_before/after
```python
# Compilar con interrupt_before
graph = builder.compile(
    checkpointer=checkpointer,
    interrupt_before=["dangerous_action"]
)

# Primera ejecución - para antes de "dangerous_action"
result = graph.invoke(input, config)

# Inspeccionar state
state = graph.get_state(config)
print(state.next)  # ['dangerous_action']

# Continuar tras aprobación
result = graph.invoke(None, config)
```

### Graph API: Modificar State
```python
# Modificar state antes de continuar
graph.update_state(
    config,
    {"messages": [("user", "Approved with changes")]}
)

# Continuar
result = graph.invoke(None, config)
```

### Functional API: interrupt() (NUEVO)
```python
from langgraph.types import interrupt, Command

@entrypoint(checkpointer=InMemorySaver())
def approval_workflow(request: dict) -> dict:
    # Procesar request...
    
    # Pausar para aprobación humana
    decision = interrupt({
        "request": request,
        "message": "Please approve or reject"
    })
    
    return {"decision": decision, "request": request}

# Primera llamada - para en interrupt
config = {"configurable": {"thread_id": "approval_1"}}
result = approval_workflow.invoke({"amount": 1000}, config)

# Resumir con decisión humana
result = approval_workflow.invoke(Command(resume="approved"), config)
```

---

## Streaming

### Modos de Streaming
```python
# values: state completo tras cada step
for state in graph.stream(input, config, stream_mode="values"):
    print(state)

# updates: solo los cambios (deltas)
for delta in graph.stream(input, config, stream_mode="updates"):
    print(delta)

# messages: tokens individuales (para UI de chat)
for msg in graph.stream(input, config, stream_mode="messages"):
    print(msg, end="", flush=True)
```

### Streaming con FastAPI
```python
from fastapi import FastAPI
from fastapi.responses import StreamingResponse

app = FastAPI()

@app.post("/chat")
async def chat(message: str, thread_id: str):
    config = {"configurable": {"thread_id": thread_id}}
    
    async def generate():
        async for event in graph.astream(
            {"messages": [("user", message)]},
            config,
            stream_mode="messages"
        ):
            yield f"data: {event}\n\n"
    
    return StreamingResponse(generate(), media_type="text/event-stream")
```

---

## Patrones Comunes

### Supervisor Pattern (Multi-Agent)
```python
from langchain.agents import create_agent

# Crear sub-agentes con create_agent
researcher = create_agent(
    model="openai:gpt-4o",
    tools=[search_tool],
    system_prompt="You are a research specialist."
)

coder = create_agent(
    model="openai:gpt-4o", 
    tools=[code_tool],
    system_prompt="You are a coding specialist."
)

# Supervisor decide qué agente usar
def supervisor_node(state):
    decision = supervisor_llm.invoke(state["messages"])
    return {"next_agent": decision.content}

def route_to_agent(state):
    return state["next_agent"]

builder = StateGraph(SupervisorState)
builder.add_node("supervisor", supervisor_node)
builder.add_node("researcher", lambda s: researcher.invoke(s))
builder.add_node("coder", lambda s: coder.invoke(s))

builder.add_conditional_edges(
    "supervisor",
    route_to_agent,
    {
        "researcher": "researcher",
        "coder": "coder",
        "FINISH": END
    }
)
```

### Map-Reduce (Parallel Execution)
```python
from langgraph.constants import Send

def continue_to_workers(state):
    """Fan-out a múltiples workers."""
    return [
        Send("worker", {"task": task})
        for task in state["tasks"]
    ]

def aggregator(state):
    """Combina resultados de workers."""
    return {"final_result": combine(state["worker_results"])}

builder.add_conditional_edges("splitter", continue_to_workers)
builder.add_edge("worker", "aggregator")
```

### Mezclar Graph API y Functional API
```python
from langgraph.func import entrypoint
from langgraph.graph import StateGraph

# Definir un grafo
builder = StateGraph(State)
# ... add nodes and edges
sub_graph = builder.compile()

# Usar el grafo dentro de un entrypoint
@entrypoint(checkpointer=InMemorySaver())
def main_workflow(inputs: dict) -> dict:
    # Llamar al grafo desde el entrypoint
    result1 = sub_graph.invoke(inputs)
    
    # Hacer más procesamiento
    result2 = some_task(result1).result()
    
    return {"graph_result": result1, "task_result": result2}
```

---

## Visualización y Debug

### Generar Diagrama (Solo Graph API)
```python
# ASCII
print(graph.get_graph().draw_ascii())

# Mermaid (para docs)
print(graph.get_graph().draw_mermaid())

# PNG (requiere graphviz)
graph.get_graph().draw_png("workflow.png")
```

**Nota**: Functional API NO soporta visualización (grafo se genera dinámicamente).

### LangSmith Tracing
```python
import os

os.environ["LANGSMITH_TRACING"] = "true"  # Nuevo en v1
os.environ["LANGSMITH_API_KEY"] = "ls_..."
os.environ["LANGSMITH_PROJECT"] = "mi-langgraph-app"
```

### Inspeccionar State History
```python
for state in graph.get_state_history(config):
    print(f"Step: {state.next}")
    print(f"State: {state.values}")
```

---

## Migración desde v0.x

### create_react_agent → create_agent
```python
# [FAIL] ANTES (deprecated)
from langgraph.prebuilt import create_react_agent
agent = create_react_agent(llm, tools, checkpointer=checkpointer)

# [PASS] AHORA
from langchain.agents import create_agent
agent = create_agent(
    model="openai:gpt-4o",
    tools=tools,
)
# Checkpointer se maneja vía LangGraph si necesitas custom workflow
```

### MemorySaver → InMemorySaver
```python
# [FAIL] ANTES
from langgraph.checkpoint.memory import MemorySaver

# [PASS] AHORA (mismo import, nombre puede variar)
from langgraph.checkpoint.memory import InMemorySaver
```

### PostgresSaver API
```python
# [FAIL] ANTES
from langgraph.checkpoint.postgres import PostgresSaver
checkpointer = PostgresSaver(conn)

# [PASS] AHORA (preferir from_conn_string)
with PostgresSaver.from_conn_string(DB_URI) as checkpointer:
    checkpointer.setup()
    graph = builder.compile(checkpointer=checkpointer)
```

---

## Checklist Producción

### Pre-Deploy
```
□ Python 3.10+ verificado
□ langgraph >= 1.0.0
□ PostgresSaver para persistencia (no InMemorySaver)
□ Connection pooling configurado
□ Thread IDs con namespace (tenant:user:session)
□ interrupt() o interrupt_before para operaciones críticas
□ Error handling en cada node/task
□ Timeouts configurados
□ LangSmith tracing activo
```

### Elegir API
```
□ ¿Necesitas visualización? → Graph API
□ ¿Código existente sin restructurar? → Functional API
□ ¿Control granular de state? → Graph API
□ ¿Parallelismo simple? → Functional API con tasks
□ ¿Time-travel debugging? → Graph API
```

### Errores Comunes
```
[FAIL] Olvidar thread_id con checkpointer
[FAIL] Usar InMemorySaver en producción
[FAIL] State muy grande (no guardar documentos completos)
[FAIL] Cycles infinitos (siempre tener condición de salida)
[FAIL] No llamar .result() en tasks (Functional API)
[FAIL] Mezclar sync/async incorrectamente
[FAIL] No llamar checkpointer.setup() con PostgreSQL
```

---

## Anti-patterns

```python
# [FAIL] MALO: Usar create_react_agent de langgraph.prebuilt
from langgraph.prebuilt import create_react_agent  # DEPRECATED

# [PASS] BUENO: Usar create_agent de langchain.agents
from langchain.agents import create_agent

# [FAIL] MALO: LCEL para comparar con LangGraph
chain = prompt | llm | parser  # LCEL deprecated

# [PASS] BUENO: create_agent para simple, LangGraph para complejo
agent = create_agent(model="openai:gpt-4o", tools=tools)

# [FAIL] MALO: InMemorySaver en producción
checkpointer = InMemorySaver()  # Solo para dev/test

# [PASS] BUENO: PostgresSaver en producción
with PostgresSaver.from_conn_string(DB_URI) as checkpointer:
    ...

# [FAIL] MALO: Olvidar .result() en tasks
@entrypoint()
def workflow(x):
    return process_task(x)  # Retorna Future, no el valor!

# [PASS] BUENO: Llamar .result()
@entrypoint()
def workflow(x):
    return process_task(x).result()
```
