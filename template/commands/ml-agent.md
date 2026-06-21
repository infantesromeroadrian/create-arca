---
description: Pipeline agentes LLM (ReAct, ReWOO, LangGraph) desde diseño. Uso: /ml-agent <objetivo>
---
Construye sistema de agentes LLM para: $ARGUMENTS

Arranca desde C4 (Design) del pipeline ML v4.0:
1. @token-optimizer → comprime contexto inicial
2. @skill-router → selecciona skills (ai-agents-engineering, langgraph, deep-agents-core)
3. @architect-ai — diseño: arquitectura multi-agent, orquestación, memory strategy
4. @ai-engineer — implementación LLM orchestration layer
5. @agent-engineer — patrones ReAct/ReWOO/Plan-and-Execute, tool calling, límites de iteración
6. @prompt-engineer — prompts de cada agente (system, planner, executor, reflector) versionados
7. @math-critic — auditoría: temperature/top-k/top-p, embeddings similarity, scoring functions
8. @ai-red-teamer — prompt injection, jailbreaks, abuse de tools
9. @model-evaluator — evals con LangSmith + métricas propias (task completion, tool success rate)
10. @cost-analyzer — coste por ejecución (tokens × iteraciones × modelos)
11. @code-critic — gate final antes de deploy

Sin límite de iteraciones ReAct = bloqueante. ADR obligatorio antes de BUILD. @math-critic bloqueante antes de @code-critic.
