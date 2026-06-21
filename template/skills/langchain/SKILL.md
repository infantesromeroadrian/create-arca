---
name: langchain
description: "LangChain ADVANCED: production patterns, middleware, structured outputs, streaming, error handling. Use for production LangChain apps. For basics (create_agent, @tool, chains), use langchain-fundamentals instead."
globs:
  - "**/langchain*.py"
  - "**/agent*.py"
  - "**/chain*.py"
  - "**/tools*.py"
effort: high
---

# LangChain Best Practices (v1.x)

> **ARCA preference:** al copiar estos snippets a producción ARCA, sustituir `"openai:gpt-4o"` y `"google-genai:gemini-2.0-flash"` por `"anthropic:claude-sonnet-4-6"` (default) o `"anthropic:claude-opus-4-8"` (high-stakes). El muestrario multi-provider es intencional para reflejar la doc oficial de LangChain v1 — la skill enseña neutralidad de proveedor, no preferencia de proveedor.

## Versiones soportadas

| Paquete | Versión |
|---------|---------|
| langchain | 1.0+ LTS (released 2025-10-20) |
| langchain-core | peer-dep with langchain (1.0+) |
| langgraph | 1.0+ |
| Python | 3.10+ (3.9 dropped) |

> Source of truth for version pinning: see `langchain-dependencies` skill. This skill focuses on production patterns; do not duplicate version data here.

## [WARN] CAMBIOS CRÍTICOS v1.0

```
┌─────────────────────────────────────────────────────────────────┐
│ ANTES (v0.x) DEPRECATED          │ AHORA (v1.x) USAR          │
├─────────────────────────────────────────────────────────────────┤
│ prompt | llm | parser (LCEL)     │ create_agent               │
│ AgentExecutor                    │ create_agent + middleware  │
│ LLMChain                         │ langchain-classic (legacy) │
│ ConversationBufferMemory         │ SummarizationMiddleware    │
│ create_openai_tools_agent        │ create_agent               │
│ Python 3.9                       │ Python 3.10+ requerido     │
└─────────────────────────────────────────────────────────────────┘
```

---

## create_agent - La Nueva API Principal

### Sintaxis Básica
```python
from langchain.agents import create_agent
from langchain_core.tools import tool

@tool
def check_weather(location: str) -> str:
    """Get weather for a location."""
    return f"Sunny in {location}"

# Crear agente (NUEVA forma recomendada)
agent = create_agent(
    model="openai:gpt-4o",  # Formato: provider:model
    tools=[check_weather],
    system_prompt="You are a helpful assistant.",
)

# Invocar
result = agent.invoke({
    "messages": [{"role": "user", "content": "What's the weather in ⟦ timezone ⟧?"}]
})

# Streaming
for chunk in agent.stream(
    {"messages": [{"role": "user", "content": "Weather in ⟦ timezone ⟧?"}]},
    stream_mode="updates"
):
    print(chunk)

# Async
result = await agent.ainvoke({
    "messages": [{"role": "user", "content": "Weather?"}]
})
```

### Modelos Soportados (Formato provider:model)
```python
# OpenAI
model="openai:gpt-4o"
model="openai:gpt-4o-mini"

# Anthropic
model="anthropic:claude-sonnet-4-6"
model="anthropic:claude-opus-4-8"

# Google
model="google-genai:gemini-2.0-flash"

# También acepta objeto BaseChatModel
from langchain_openai import ChatOpenAI
model = ChatOpenAI(model="gpt-4o", temperature=0)
agent = create_agent(model=model, tools=[...])
```

---

## Middleware - Sistema de Extensibilidad

### Concepto
```
Request Flow:
User Input
    → Middleware 1: before_model
    → Middleware 2: before_model
    → Middleware 1,2: modify_model_request
    → LLM Call
    ← Middleware 2: after_model
    ← Middleware 1: after_model
    ← Final Response
```

### Middleware Built-in

#### 1. HumanInTheLoopMiddleware (Aprobación Humana)
```python
from langchain.agents import create_agent
from langchain.agents.middleware import HumanInTheLoopMiddleware
from langgraph.checkpoint.memory import MemorySaver

@tool
def process_refund(amount: float, reason: str) -> str:
    """Process a customer refund."""
    return f"Refund of ${amount} processed"

agent = create_agent(
    model="openai:gpt-4o",
    tools=[process_refund],
    middleware=[
        HumanInTheLoopMiddleware(
            tools=["process_refund"],  # Tools que requieren aprobación
        )
    ],
    checkpointer=MemorySaver(),  # Requerido para HITL
)
```

#### 2. SummarizationMiddleware (Reemplaza Memory)
```python
from langchain.agents.middleware import SummarizationMiddleware

agent = create_agent(
    model="openai:gpt-4o",
    tools=[search_tool],
    middleware=[
        SummarizationMiddleware(
            max_tokens=4000,  # Trigger summarization cuando excede
            summary_model="openai:gpt-4o-mini",  # Modelo para resumir
        )
    ],
)
```

#### 3. PIIMiddleware (Protección de Datos)
```python
from langchain.agents.middleware import PIIMiddleware
import re

agent = create_agent(
    model="openai:gpt-4o",
    tools=[],
    middleware=[
        # Bloquear API keys
        PIIMiddleware(
            "api_key",
            detector=r"sk-[a-zA-Z0-9]{32}",
            strategy="block",
        ),
        # Enmascarar teléfonos
        PIIMiddleware(
            "phone_number",
            detector=re.compile(r"\+?\d{1,3}[\s.-]?\d{3,4}[\s.-]?\d{4}"),
            strategy="mask",
        ),
    ],
)
```

#### 4. ToolRetryMiddleware (Reintentos)
```python
from langchain.agents.middleware import ToolRetryMiddleware

agent = create_agent(
    model="openai:gpt-4o",
    tools=[api_tool, database_tool],
    middleware=[
        ToolRetryMiddleware(
            max_retries=3,
            backoff_factor=2.0,
            initial_delay=1.0,
            tools=["api_tool"],  # Solo para tools específicos
            retry_on=(ConnectionError, TimeoutError),
            on_failure="continue",  # o "error" para re-raise
        )
    ],
)
```

#### 5. ModelRetryMiddleware (Reintentos de LLM)
```python
from langchain.agents.middleware import ModelRetryMiddleware

agent = create_agent(
    model="openai:gpt-4o",
    tools=[search_tool],
    middleware=[
        ModelRetryMiddleware(
            max_retries=3,
            backoff_factor=2.0,
            initial_delay=1.0,
        )
    ],
)
```

#### 6. LLMToolSelectorMiddleware (Selección de Tools)
```python
from langchain.agents.middleware import LLMToolSelectorMiddleware

# Cuando tienes MUCHOS tools, pre-filtra los relevantes
agent = create_agent(
    model="openai:gpt-4o",
    tools=[tool1, tool2, tool3, tool4, tool5],  # Muchos tools
    middleware=[
        LLMToolSelectorMiddleware(max_tools=3)  # Pre-selecciona 3 más relevantes
    ],
)
```

### Custom Middleware con Decoradores
```python
from langchain.agents.middleware import before_model, after_model, wrap_model_call

@before_model
def log_request(request, state, runtime):
    """Log antes de cada llamada al modelo."""
    print(f"Calling model with {len(state['messages'])} messages")
    return None  # Continuar normalmente

@after_model
def log_response(response, state, runtime):
    """Log después de cada respuesta."""
    print(f"Model responded with {len(response.content)} chars")
    return None

@wrap_model_call
def retry_on_error(request, handler):
    """Custom retry logic."""
    max_retries = 3
    for attempt in range(max_retries):
        try:
            return handler(request)
        except Exception as e:
            if attempt == max_retries - 1:
                raise
            print(f"Retry {attempt + 1}/{max_retries}")

agent = create_agent(
    model="openai:gpt-4o",
    tools=[search_tool],
    middleware=[log_request, log_response, retry_on_error],
)
```

### Dynamic Prompt con Middleware
```python
from typing import TypedDict
from langchain.agents.middleware import dynamic_prompt, ModelRequest

class Context(TypedDict):
    user_role: str

@dynamic_prompt
def user_role_prompt(request: ModelRequest) -> str:
    """Sistema prompt dinámico basado en contexto."""
    user_role = request.runtime.context.get("user_role", "user")
    base = "You are a helpful assistant."
    
    if user_role == "expert":
        return f"{base} Provide detailed technical responses."
    elif user_role == "beginner":
        return f"{base} Explain concepts simply."
    return base

agent = create_agent(
    model="openai:gpt-4o",
    tools=[web_search],
    middleware=[user_role_prompt],
    context_schema=Context,
)

# Usar con contexto
result = agent.invoke(
    {"messages": [{"role": "user", "content": "Explain ML"}]},
    context={"user_role": "expert"}
)
```

---

## Tools - Definición

### @tool Decorator (Recomendado)
```python
from langchain_core.tools import tool
from typing import Optional

@tool
def search_database(query: str, limit: int = 10) -> str:
    """
    Search the database for information.
    
    Args:
        query: Search term
        limit: Maximum results (default 10)
    
    Returns:
        Search results as string
    """
    # Implementación...
    return f"Results for: {query}"

# El docstring es la descripción que ve el LLM
# Los type hints definen el schema automáticamente
```

### Tool con Pydantic Schema
```python
from langchain_core.tools import tool
from pydantic import BaseModel, Field

class SearchInput(BaseModel):
    query: str = Field(description="Search query")
    max_results: int = Field(default=5, ge=1, le=20)
    filters: list[str] = Field(default_factory=list)

@tool(args_schema=SearchInput)
def advanced_search(query: str, max_results: int, filters: list[str]) -> str:
    """Advanced search with filters."""
    return f"Searching: {query} with {len(filters)} filters"
```

### Injected State (Acceso al Estado del Agente)
```python
from typing_extensions import Annotated
from langchain_core.tools import tool, InjectedState

@tool
def context_aware_tool(
    query: str,
    state: Annotated[dict, InjectedState]
) -> str:
    """Tool that can access agent state."""
    message_count = len(state.get('messages', []))
    return f"Query: {query}, Previous messages: {message_count}"
```

---

## Structured Outputs

### Con response_format (Recomendado v1.x)
```python
from pydantic import BaseModel, Field
from langchain.agents import create_agent

class MovieReview(BaseModel):
    """Structured movie review."""
    title: str = Field(description="Movie title")
    rating: int = Field(ge=1, le=10, description="Rating 1-10")
    pros: list[str] = Field(description="Positive aspects")
    cons: list[str] = Field(description="Negative aspects")
    summary: str = Field(description="Brief summary")

agent = create_agent(
    model="openai:gpt-4o",
    tools=[],
    response_format=MovieReview,  # Structured output integrado
)

result = agent.invoke({
    "messages": [{"role": "user", "content": "Review Inception"}]
})
# result contiene MovieReview tipado
```

### Provider Strategy (Control de Método)
```python
from langchain.agents import create_agent, ProviderStrategy

# Forzar uso de function calling nativo
agent = create_agent(
    model="openai:gpt-4o",
    tools=[],
    response_format=ProviderStrategy(MovieReview),
)
```

---

## Model Profiles (v1.1+)

```python
from langchain.chat_models import init_chat_model

# Los modelos ahora exponen sus capacidades
model = init_chat_model("openai:gpt-4o")
print(model.profile)
# {
#   "supports_tool_calling": True,
#   "supports_structured_output": True,
#   "supports_json_mode": True,
#   ...
# }

# El middleware usa profiles automáticamente
# para decidir cómo llamar al modelo
```

---

## RAG con create_agent

```python
from langchain.agents import create_agent
from langchain_core.tools import tool
from langchain_openai import OpenAIEmbeddings
from langchain_community.vectorstores import FAISS

# 1. Setup vector store
embeddings = OpenAIEmbeddings()
vectorstore = FAISS.from_documents(documents, embeddings)
retriever = vectorstore.as_retriever(search_kwargs={"k": 5})

# 2. Crear tool de retrieval
@tool
def search_knowledge_base(query: str) -> str:
    """Search the knowledge base for relevant information."""
    docs = retriever.invoke(query)
    return "\n\n".join(doc.page_content for doc in docs)

# 3. Crear agente RAG
rag_agent = create_agent(
    model="openai:gpt-4o",
    tools=[search_knowledge_base],
    system_prompt="""You are a helpful assistant. 
    Always search the knowledge base before answering.
    Base your answers ONLY on the retrieved information.""",
)

result = rag_agent.invoke({
    "messages": [{"role": "user", "content": "What is the refund policy?"}]
})
```

---

## Observabilidad con LangSmith

### Configuración
```python
import os

os.environ["LANGSMITH_TRACING"] = "true"  # Nuevo en v1.x
os.environ["LANGSMITH_API_KEY"] = "ls_..."
os.environ["LANGSMITH_PROJECT"] = "my-project"

# Automáticamente traza todas las llamadas de create_agent
```

### Tags y Metadata en create_agent
```python
agent = create_agent(
    model="openai:gpt-4o",
    tools=[search_tool],
    name="research-agent",  # Nombre para tracing
)

# Config en runtime
result = agent.invoke(
    {"messages": [...]},
    config={
        "tags": ["production", "v2"],
        "metadata": {"user_id": "123", "session": "abc"}
    }
)
```

---

## Streaming para UX

### Streaming Básico
```python
agent = create_agent(model="openai:gpt-4o", tools=[search])

for chunk in agent.stream(
    {"messages": [{"role": "user", "content": "Research AI trends"}]},
    stream_mode="updates"  # o "values", "messages"
):
    print(chunk)
```

### Con FastAPI
```python
from fastapi import FastAPI
from fastapi.responses import StreamingResponse

app = FastAPI()

@app.post("/chat")
async def chat(question: str):
    async def generate():
        async for chunk in agent.astream(
            {"messages": [{"role": "user", "content": question}]},
            stream_mode="messages"
        ):
            if hasattr(chunk, 'content'):
                yield f"data: {chunk.content}\n\n"
    
    return StreamingResponse(generate(), media_type="text/event-stream")
```

---

## MCP Integration (Model Context Protocol)

```python
from langchain_mcp_adapters.client import MultiServerMCPClient
from langchain.agents import create_agent

async def main():
    # Conectar a MCP servers
    mcp_client = MultiServerMCPClient({
        "filesystem": {"command": "npx", "args": ["-y", "@anthropic/mcp-filesystem"]},
        "github": {"command": "npx", "args": ["-y", "@anthropic/mcp-github"]},
    })
    
    # Obtener tools de MCP
    mcp_tools = await mcp_client.get_tools()
    
    # Usar en agente
    agent = create_agent(
        model="anthropic:claude-sonnet-4-6",
        tools=mcp_tools,
    )
    
    result = await agent.ainvoke({
        "messages": [{"role": "user", "content": "List files in current dir"}]
    })
```

---

## Migración desde v0.x

### Instalar
```bash
# Actualizar
uv pip install --upgrade langchain

# Si necesitas código legacy
uv pip install langchain-classic
```

### Cambios de Imports
```python
# [FAIL] ANTES (v0.x)
from langchain.chains import LLMChain
from langchain.agents import AgentExecutor, create_openai_tools_agent
from langchain.memory import ConversationBufferMemory

# [PASS] AHORA (v1.x)
from langchain.agents import create_agent
from langchain.agents.middleware import (
    SummarizationMiddleware,
    HumanInTheLoopMiddleware,
)

# Si NECESITAS código legacy temporalmente:
from langchain_classic.chains import LLMChain
from langchain_classic.agents import AgentExecutor
```

### Ejemplo de Migración
```python
# [FAIL] ANTES (v0.x) - NO USAR
from langchain_openai import ChatOpenAI
from langchain.agents import AgentExecutor, create_openai_tools_agent
from langchain_core.prompts import ChatPromptTemplate

prompt = ChatPromptTemplate.from_messages([
    ("system", "You are a helpful assistant."),
    ("placeholder", "{chat_history}"),
    ("user", "{input}"),
    ("placeholder", "{agent_scratchpad}")
])
llm = ChatOpenAI(model="gpt-4o")
agent = create_openai_tools_agent(llm, tools, prompt)
executor = AgentExecutor(agent=agent, tools=tools)
result = executor.invoke({"input": "Hello"})

# [PASS] AHORA (v1.x) - USAR ESTO
from langchain.agents import create_agent
from langchain.agents.middleware import SummarizationMiddleware

agent = create_agent(
    model="openai:gpt-4o",
    tools=tools,
    system_prompt="You are a helpful assistant.",
    middleware=[SummarizationMiddleware()],  # Reemplaza memory
)
result = agent.invoke({
    "messages": [{"role": "user", "content": "Hello"}]
})
```

---

## Cuándo Usar Qué

| Caso de Uso | Herramienta |
|-------------|-------------|
| Agente simple con tools | `create_agent` |
| RAG | `create_agent` + retriever tool |
| Aprobación humana | `HumanInTheLoopMiddleware` |
| Conversaciones largas | `SummarizationMiddleware` |
| Protección de datos | `PIIMiddleware` |
| Workflows complejos con grafos | LangGraph |
| Multi-agent orchestration | LangGraph |
| Código legacy | `langchain-classic` |

### Regla 2025
```
create_agent para agentes estándar
LangGraph para workflows complejos y multi-agent
Middleware para extensibilidad
langchain-classic solo para migración gradual
```

---

## Checklist Producción

### Pre-Deploy
```
□ Python 3.10+ verificado
□ langchain pinned to LTS line (>= 1.0, < 2.0) — see `langchain-dependencies` skill
□ create_agent usado (no AgentExecutor)
□ Middleware configurado (retry, summarization)
□ LangSmith tracing habilitado
□ Structured outputs con Pydantic
□ Timeouts configurados
□ Secrets en variables de entorno
```

### Middleware Recomendado para Producción
```python
from langchain.agents import create_agent
from langchain.agents.middleware import (
    ModelRetryMiddleware,
    ToolRetryMiddleware,
    SummarizationMiddleware,
    PIIMiddleware,
)

production_agent = create_agent(
    model="anthropic:claude-sonnet-4-6",
    tools=tools,
    middleware=[
        ModelRetryMiddleware(max_retries=3),
        ToolRetryMiddleware(max_retries=2),
        SummarizationMiddleware(max_tokens=8000),
        PIIMiddleware("api_key", detector=r"sk-\w+", strategy="block"),
    ],
)
```

### Monitoreo
```
□ Latencia por step (LangSmith)
□ Token usage tracking
□ Error rates por modelo
□ Feedback collection
□ Cost monitoring
```

---

## Anti-patterns

```python
# [FAIL] MALO: LCEL pipes (deprecated en v1.x)
chain = prompt | llm | parser

# [PASS] BUENO: create_agent
agent = create_agent(model="openai:gpt-4o", tools=[])

# [FAIL] MALO: AgentExecutor
executor = AgentExecutor(agent=agent, tools=tools)

# [PASS] BUENO: create_agent directo
agent = create_agent(model="openai:gpt-4o", tools=tools)

# [FAIL] MALO: ConversationBufferMemory
memory = ConversationBufferMemory()

# [PASS] BUENO: SummarizationMiddleware
middleware=[SummarizationMiddleware()]

# [FAIL] MALO: Python 3.9
python_requires = ">=3.9"

# [PASS] BUENO: Python 3.10+
python_requires = ">=3.10"

# [FAIL] MALO: Modelos desactualizados
model="anthropic:claude-3-sonnet-20240229"

# [PASS] BUENO: Modelos actuales
model="anthropic:claude-sonnet-4-6"
```
