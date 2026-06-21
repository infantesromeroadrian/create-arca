---
description: Pipeline seguridad / red teaming C1→C10. Uso: /sec-tool <objetivo>
---
Construye herramienta de seguridad / red teaming para: $ARGUMENTS

Pipeline seguridad completo (mapeado a 14 ciclos ML v4.0):
1. @token-optimizer → comprime contexto inicial
2. @skill-router → selecciona skills (owasp-security, cybersecurity, ml-security)
3. **C1 Discovery** — @project-planner: scope, autorización, límites éticos explícitos + tickets Jira con hitos
4. **C4 Design** — @architect-ai: threat model, arquitectura, telemetría, ADRs firmados
5. **C6 Build** — @ai-red-teamer: implementación de vulnerabilidades, adversarial attacks, prompt injection tests
6. **C8 Quality** — @code-critic + @ai-red-teamer pentest interno + @evals-engineer si dangerous capability evals aplican
7. **C10 Deploy** — @chief-architect (BLOQUEANTE) revisión final seguridad + @trust-and-safety-engineer si producto público
8. **C10 Deploy** — @deployment solo si scope y autorización están registrados por escrito

BLOQUEANTE: sin autorización escrita no se despliega. Sin threat model no se implementa. CVP de Anthropic vigente para dual-use cybersecurity.
