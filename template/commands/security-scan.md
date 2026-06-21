---
description: Auditoría de seguridad completa antes de deploy
---
Auditoría de seguridad para: $ARGUMENTS

Usa skill owasp-security. Lanza en paralelo:
1. @ai-red-teamer — adversarial + prompt injection (si hay LLMs)
2. @python-specialist — secretos hardcodeados, deps vulnerables
3. @devops — configuración infra, permisos, network policies

Resultado: PASS / FAIL con lista de bloqueantes ordenada por severidad.
FAIL = no deploy.
