---
name: ai-agents-engineering
description: Complete guide for building AI agents including ReAct pattern, LangGraph, multi-agent orchestration (CrewAI, AutoGen), tool use, memory systems, and production patterns. Use when building autonomous AI systems, chatbots with tools, or multi-agent workflows.
---

# AI Agents

## Framework Selection 2025

| Framework | Best For | Complexity |
|-----------|----------|------------|
| **LangGraph** | Production agents, complex state machines | High control |
| **CrewAI** | Role-based teams, rapid prototyping | Low barrier |
| **AutoGen/MS Agent Framework** | Enterprise, Azure integration | Enterprise |
| **OpenAI Agents SDK** | OpenAI ecosystem, simple agents | Lowest |
| **LlamaIndex** | RAG-heavy agents, document workflows | Moderate |

**Rule of thumb**: Start with LangGraph for production, CrewAI for prototypes.

---

## Core Patterns

### ReAct (Reasoning + Acting)

The foundational pattern: Think → Act → Observe → Repeat

```python
from langchain.agents import create_agent
from langchain_anthropic import ChatAnthropic
from langchain_core.tools import tool

@tool
def search(query: str) -> str:
    """Search the web for current information."""
    # Tavily, Serper, or custom search
    return search_api.search(query)

@tool  
def calculate(expression: str) -> float:
    """Evaluate mathematical expressions safely."""
    import ast
    return float(ast.literal_eval(expression))

llm = ChatAnthropic(model="claude-sonnet-4-6")
agent = create_agent(llm, tools=[search, calculate])

# Run
result = agent.invoke({
    "messages": [("user", "What's the GDP of France times 2?")]
})
```

### Plan-and-Execute

Better for complex, multi-step tasks:

```python
from langgraph.graph import StateGraph, START, END
from typing import TypedDict, List, Annotated
import operator

class PlanExecuteState(TypedDict):
    input: str
    plan: List[str]
    past_steps: Annotated[List[tuple], operator.add]
    response: str

def planner(state: PlanExecuteState):
    """Generate multi-step plan."""
    plan = llm.invoke(f"Create a plan to: {state['input']}")
    return {"plan": parse_plan(plan)}

def executor(state: PlanExecuteState):
    """Execute current step."""
    current_step = state["plan"][0]
    result = react_agent.invoke({"messages": [("user", current_step)]})
    return {
        "past_steps": [(current_step, result)],
        "plan": state["plan"][1:]  # Remove completed step
    }

def should_continue(state: PlanExecuteState):
    return "executor" if state["plan"] else "respond"

# Build graph
workflow = StateGraph(PlanExecuteState)
workflow.add_node("planner", planner)
workflow.add_node("executor", executor)
workflow.add_node("respond", generate_response)

workflow.add_edge(START, "planner")
workflow.add_edge("planner", "executor")
workflow.add_conditional_edges("executor", should_continue)
workflow.add_edge("respond", END)

agent = workflow.compile()
```

---

## LangGraph Deep Dive

### State Management

```python
from langgraph.graph import StateGraph, MessagesState
from langgraph.checkpoint.memory import MemorySaver

# Built-in message state
class AgentState(MessagesState):
    # Extends with custom fields
    current_task: str
    completed_tasks: List[str]
    context: dict

# Checkpointing for persistence
memory = MemorySaver()
app = workflow.compile(checkpointer=memory)

# Thread-based conversations
config = {"configurable": {"thread_id": "user-123"}}
result = app.invoke({"messages": [...]}, config)

# Resume later
result = app.invoke({"messages": [("user", "continue")]}, config)
```

### Human-in-the-Loop

```python
from langgraph.prebuilt import ToolNode

# Interrupt before sensitive tools
def should_interrupt(state):
    last_message = state["messages"][-1]
    if hasattr(last_message, "tool_calls"):
        for tc in last_message.tool_calls:
            if tc["name"] in ["delete_file", "send_email"]:
                return "interrupt"
    return "continue"

workflow.add_conditional_edges(
    "agent",
    should_interrupt,
    {"interrupt": "human_review", "continue": "tools"}
)

# At runtime
try:
    result = app.invoke(input, config)
except GraphInterrupt:
    # Show user what's pending
    pending = app.get_state(config).next
    # User approves...
    app.update_state(config, {"approved": True})
    result = app.invoke(None, config)  # Resume
```

### Streaming

```python
# Stream events
async for event in app.astream_events(input, config, version="v2"):
    if event["event"] == "on_chat_model_stream":
        print(event["data"]["chunk"].content, end="")
    elif event["event"] == "on_tool_start":
        print(f"\n🔧 Using: {event['name']}")

# Stream tokens
for chunk in app.stream(input, config, stream_mode="values"):
    print(chunk["messages"][-1].content)
```

---

## Tool Design

### Best Practices

```python
from langchain_core.tools import tool
from pydantic import BaseModel, Field

# 1. Clear descriptions
@tool
def get_weather(
    city: str = Field(description="City name, e.g., 'San Francisco'"),
    units: str = Field(default="celsius", description="Temperature units")
) -> str:
    """Get current weather for a city.
    
    Use when user asks about weather, temperature, or forecast.
    Returns temperature, conditions, and humidity.
    """
    return weather_api.get(city, units)

# 2. Structured input/output
class SearchInput(BaseModel):
    query: str = Field(description="Search query")
    max_results: int = Field(default=5, ge=1, le=20)

class SearchResult(BaseModel):
    title: str
    url: str
    snippet: str

@tool(args_schema=SearchInput)
def web_search(query: str, max_results: int = 5) -> List[SearchResult]:
    """Search the web and return structured results."""
    ...

# 3. Error handling
@tool
def database_query(sql: str) -> str:
    """Execute read-only SQL query."""
    try:
        if not sql.strip().upper().startswith("SELECT"):
            return "Error: Only SELECT queries allowed"
        return db.execute(sql)
    except Exception as e:
        return f"Error: {str(e)}"
```

### Tool Categories

| Category | Examples | Notes |
|----------|----------|-------|
| Information | Search, RAG, APIs | Most common |
| Action | Email, file ops, DB writes | Need approval |
| Computation | Calculator, code exec | Sandboxed |
| Communication | Slack, notifications | Rate limited |

---

## Multi-Agent Systems

### CrewAI (Role-Based)

```python
from crewai import Agent, Task, Crew, Process

researcher = Agent(
    role="Senior Researcher",
    goal="Find accurate, comprehensive information",
    backstory="Expert at synthesizing complex information",
    tools=[search_tool, scrape_tool],
    llm="anthropic/claude-sonnet-4-6",
    verbose=True,
)

writer = Agent(
    role="Technical Writer",
    goal="Create clear, engaging content",
    backstory="Skilled at explaining complex topics simply",
    llm="anthropic/claude-sonnet-4-6",
)

research_task = Task(
    description="Research {topic} thoroughly",
    expected_output="Comprehensive research notes with sources",
    agent=researcher,
)

write_task = Task(
    description="Write article based on research",
    expected_output="Well-structured article, 1000 words",
    agent=writer,
    context=[research_task],  # Depends on research
)

crew = Crew(
    agents=[researcher, writer],
    tasks=[research_task, write_task],
    process=Process.sequential,  # or Process.hierarchical
    verbose=True,
)

result = crew.kickoff(inputs={"topic": "Quantum Computing 2025"})
```

### LangGraph Multi-Agent

```python
from langgraph.graph import StateGraph, MessagesState

class MultiAgentState(MessagesState):
    next_agent: str

def researcher_node(state):
    response = researcher_agent.invoke(state["messages"])
    return {"messages": [response], "next_agent": "writer"}

def writer_node(state):
    response = writer_agent.invoke(state["messages"])
    return {"messages": [response], "next_agent": "reviewer"}

def router(state):
    return state["next_agent"]

workflow = StateGraph(MultiAgentState)
workflow.add_node("researcher", researcher_node)
workflow.add_node("writer", writer_node)
workflow.add_node("reviewer", reviewer_node)

workflow.add_conditional_edges("researcher", router)
workflow.add_conditional_edges("writer", router)
workflow.add_edge("reviewer", END)

workflow.set_entry_point("researcher")
multi_agent = workflow.compile()
```

---

## Memory Systems

### Short-Term (Conversation)

```python
from langgraph.checkpoint.memory import MemorySaver
from langgraph.checkpoint.sqlite import SqliteSaver

# In-memory (dev)
memory = MemorySaver()

# Persistent (prod)
memory = SqliteSaver.from_conn_string("sqlite:///agent.db")

app = workflow.compile(checkpointer=memory)
```

### Long-Term (Cross-Session)

```python
from langchain_community.vectorstores import Chroma
from langchain_openai import OpenAIEmbeddings

# Vector store for semantic memory
memory_store = Chroma(
    collection_name="agent_memory",
    embedding_function=OpenAIEmbeddings(),
    persist_directory="./memory"
)

def save_memory(interaction: str, metadata: dict):
    memory_store.add_texts([interaction], metadatas=[metadata])

def recall_memory(query: str, k: int = 5):
    return memory_store.similarity_search(query, k=k)

# Use in agent
@tool
def recall(query: str) -> str:
    """Recall relevant past interactions."""
    memories = recall_memory(query)
    return "\n".join([m.page_content for m in memories])
```

---

## Production Patterns

### Observability

```python
# LangSmith tracing
import os
os.environ["LANGCHAIN_TRACING_V2"] = "true"
os.environ["LANGCHAIN_API_KEY"] = "..."

# Custom callbacks
from langchain_core.callbacks import BaseCallbackHandler

class MetricsCallback(BaseCallbackHandler):
    def on_llm_start(self, serialized, prompts, **kwargs):
        self.start_time = time.time()
    
    def on_llm_end(self, response, **kwargs):
        latency = time.time() - self.start_time
        metrics.histogram("llm_latency", latency)
        metrics.counter("llm_tokens", response.llm_output["token_usage"]["total_tokens"])
```

### Error Handling

```python
from tenacity import retry, stop_after_attempt, wait_exponential

@retry(stop=stop_after_attempt(3), wait=wait_exponential(multiplier=1, max=10))
def robust_tool_call(tool, input):
    try:
        return tool.invoke(input)
    except RateLimitError:
        raise  # Retry
    except Exception as e:
        return f"Tool failed: {str(e)}"  # Don't retry, return error

# In workflow
def safe_executor(state):
    try:
        result = agent.invoke(state)
        return {"messages": result["messages"]}
    except Exception as e:
        return {"messages": [AIMessage(content=f"I encountered an error: {e}")]}
```

### Cost Control

```python
from langchain_core.callbacks import get_openai_callback

# Track costs
with get_openai_callback() as cb:
    result = agent.invoke(input)
    print(f"Cost: ${cb.total_cost:.4f}")

# Set limits
MAX_ITERATIONS = 10
MAX_TOKENS = 10000

def check_limits(state):
    if state.get("iterations", 0) > MAX_ITERATIONS:
        return "force_respond"
    return "continue"
```

---

## Decision Framework

```
Is the task single-step?
├─ Yes → Simple LLM call, no agent needed
└─ No → Does it need tools?
    ├─ No → Chain of prompts
    └─ Yes → Is flow predictable?
        ├─ Yes → Plan-and-Execute
        └─ No → ReAct agent
            └─ Multiple specialized roles?
                ├─ Yes → Multi-agent (CrewAI/LangGraph)
                └─ No → Single agent with tools
```

## Anti-patterns

| [FAIL] Don't | [PASS] Do |
|----------|-------|
| Let agent loop infinitely | Set max iterations |
| Use vague tool descriptions | Write clear, specific descriptions |
| Skip human review for actions | Add approval for sensitive ops |
| Single monolithic agent | Specialized agents for complex tasks |
| No error handling | Graceful degradation |
| Ignore token costs | Monitor and set budgets |
