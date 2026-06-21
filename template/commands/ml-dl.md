---
description: Pipeline Deep Learning completo desde diseño hasta fine-tuning. Uso: /ml-dl <objetivo>
---
Construye pipeline DL / fine-tuning para: $ARGUMENTS

Arranca desde C4 (Design) del pipeline ML v4.0:
1. @token-optimizer → comprime contexto inicial
2. @skill-router → selecciona skills (dl-engineering, llm-engineering, inference-optimization)
3. @data-validator (BLOQUEANTE) → dataset de fine-tuning: duplicados, leakage train/val, calidad de etiquetas, cobertura
4. @architect-ai — diseño: arquitectura, loss, optimizer, scheduler, VRAM budget (⟦ gpu ⟧)
5. @dl-engineer — implementación: training loop, mixed precision, gradient clipping, QLoRA/LoRA
6. @math-critic — auditoría matemática: gradientes, estabilidad numérica, attention scaling
7. @gpu-engineer — optimización GPU calibrada a 
8. @prompt-engineer — si fine-tuning instruction-following: diseño de prompt templates + system prompts
9. @model-evaluator — métricas + baseline + significancia estadística
10. @perf-engineer — latencia inferencia + quantización INT8/INT4
11. @cost-analyzer — coste de training (GPU-hours) + coste de inferencia
12. @code-critic — gate final antes de deploy

ADR obligatorio antes de BUILD. @data-validator bloqueante antes de training. @math-critic bloqueante antes de @code-critic.
