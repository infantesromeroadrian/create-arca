---
name: team-security
description: Team preset para auditoría de seguridad — 3 amenazadores en paralelo (script-kiddie externo, insider, supply-chain). Invócame cuando ⟦ user_name ⟧ diga /team-security, audita esto de seguridad, antes de deploy público, hay que pasar security gate, o similar.
when_to_use: auditoría pre-deploy, review de endpoint público, revisión tras PR tocando auth/crypto/IO externa
argument-hint: "<target: path, endpoint, PR, o componente>"
disable-model-invocation: false
user-invocable: true
allowed-tools: Read Grep Glob Bash(git diff *) Bash(gh pr *)
model: opus
effort: high
---

# /team-security — 3 amenazadores en paralelo

⟦ user_name ⟧ pidió auditoría de seguridad sobre: `$ARGUMENTS`

Variación de `/voting-review --mode security` con 3 perfiles de amenazador distintos (no 3 ejes técnicos). Requiere `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`.

## Preflight

1. Verificar que hay autorización (es propio código, o CVP scope).
2. Si el target es código live en producción → confirmar a ⟦ user_name ⟧ que este skill es audit READ-ONLY, no inyecta exploits.
3. Si hay secretos en el diff → @ai-red-teamer debe flagearlo inmediatamente antes de seguir.

## Team (3 amenazadores)

| Teammate | Agent | Perfil de amenaza | Enfoque |
|---|---|---|---|
| **script-kiddie** | `ai-red-teamer` (skill `owasp-security`) | externo, sin conocimiento interno | OWASP Top 10, injection, auth bypass, CVEs conocidas en deps |
| **insider** | `ai-red-teamer` (skill `cybersecurity`) | interno con acceso parcial | privesc, credential reuse, secrets en logs/code, exfil lateral |
| **supply-chain** | `code-critic` + skill `owasp-security` | amenaza vía deps | lockfile diffs, unknown maintainers, typosquatting, package-confusion |

## Flujo

### Round 1 — discovery paralelo

Los 3 amenazadores escanean el mismo target desde su perfil. Cada uno produce lista ranked de findings con severidad CVSS-like (CRITICAL/HIGH/MEDIUM/LOW/INFO).

### Round 2 — adversarial cross

- **script-kiddie** lee findings de insider → "¿qué exploit público convierte el issue de insider en un vector externo?"
- **insider** lee findings de script-kiddie → "¿cómo amplifica acceso interno este issue externo?"
- **supply-chain** lee ambos → "¿algún finding se dispara solo cuando la dep X se actualiza?"

### Round 3 — consolidación

Lead sintetiza:
- **Explotable con privilegios=0** (desde internet) → CRITICAL automático
- **Requiere insider** (privilegios>0) → HIGH máximo
- **Requiere compromiso de dep** → severidad según blast radius

## Output

```markdown
## /team-security — {target}

### CRITICAL (explotable externo, pre-auth)
- <file:line> — <descripción> — vector: <cómo>.

### HIGH (post-auth / insider amplification)
- ...

### MEDIUM (requiere combinación de condiciones)
- ...

### Dependencies flagged
- <package>@<version> — razón (CVE, maintainer, typosquat).

### Verdict
- BLOQUEANTE para deploy si hay ≥1 CRITICAL.
- Revisar si hay ≥3 HIGH.
- OK para deploy si solo MEDIUM/LOW con plan de remediación.

### Remediación priorizada
1. {finding} → {acción concreta file:line + quién lo hace}
```

## Reglas duras

- **Secretos expuestos = CRITICAL instantáneo**. Sin negociación, sin "pero es un placeholder".
- **No reportar findings sin file:line**. Si no se puede localizar, explicar por qué (cross-cutting, config runtime, etc).
- **No dejar dependency findings sin versión exacta**. "Vulnerable crypto" no es útil; "pyca/cryptography < 42.0.2 (CVE-2024-X)" sí.
- **No asumir mitigaciones no verificadas**. Si el code dice "input sanitizado" y no hay unit test que lo pruebe, el finding sigue abierto.

**ultrathink** en Round 2 cross. El valor del team vs un solo auditor está en los findings que emergen del amplification cross — no en los que cada uno encuentra solo.
