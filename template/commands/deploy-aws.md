---
description: Deploy a AWS con checklist completo de seguridad y rollback
---
Deploy a AWS para: $ARGUMENTS

Secuencia obligatoria:
1. @chief-architect — revisión arquitectural BLOQUEANTE
2. @ai-red-teamer — security audit
3. @aws-engineer — ejecuta deploy con CDK/SAM
4. @monitoring — verifica alertas post-deploy

No ejecutar paso siguiente sin ✓ del anterior.
Rollback plan documentado antes de iniciar paso 3 (deploy AWS). En el contexto C10 Deploy del pipeline ML v4.0, esto es parte del gate bloqueante de @chief-architect (rollback path en topología Excalidraw + rollback ejecutable <5min).
