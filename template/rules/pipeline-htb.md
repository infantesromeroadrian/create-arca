---
paths:
  - "**/HTB/**"
  - "**/CTF/**"
  - "**/loot/**"
  - "**/exploits/**"
  - "**/flags/**"
  - "**/*.ovpn"
---

# ARCA Pipeline HTB — 6 Fases (CTF Easy/Medium)

Orquestador: `@htb-orchestrator` — agente master que dirige el pipeline y coordina a `@htb-recon`, `@cve-hunter`, `@credential-hunter`, `@exploit-executor` y `@flag-validator`. Activación: `/htb-new <ip> <name>` o `/htb-resume`.

Aplica cuando el proyecto es una máquina HTB, CTF, o pentest autorizado. Solo bajo CVP de Anthropic y scope HTB legítimo (`10.129.x.x` / `10.10.11.x`).

**F0** SETUP: crear estructura `nmap/ loot/ exploits/ notes/ flags/` en el directorio de la máquina. Registrar dificultad en `loot/state.json`.

**F1** RECON: @htb-recon → servicios + versiones exactas → `loot/recon.json`. Sin análisis, solo inventario.

**F1.5** FAST-PATH (Easy/Medium only): Si @htb-recon identifica framework + version exacta en los primeros 5 minutos (e.g. "React 19.0.0", "Gogs 0.13.3"), CORTAR recon profundo y escalar a F2 inmediatamente con lo que hay. No esperar a fuzzing completo. Easy boxes premian recognition, no profundidad.

**F2** CVE GATE: @cve-hunter por cada servicio versionado (BLOQUEANTE). Devuelve ranking de CVEs con PoC público. Si hay CVE viable → F4 directo. **En Easy/Medium, lanzar @cve-hunter EN PARALELO a @htb-recon desde F1** — no esperar a que recon termine. El CVE-hunter puede empezar con los servicios del nmap inicial mientras recon profundiza.

**F2.5** ABORT SIGNAL: Si @cve-hunter encuentra CVE con CVSS >= 9.0 + PoC público + applicability confirmed, emitir señal de abort a agentes paralelos (@credential-hunter, @htb-recon si aún corre). No gastar tokens en vectores secundarios cuando hay RCE unauthenticado confirmado.

**F3** CRED HUNT: @credential-hunter se dispara automáticamente cada vez que aparece un secreto nuevo (env vars, tokens, passwords leaked). Cross-service reuse por default. **Respeta abort signal de F2.5** — si @cve-hunter ya tiene RCE confirmado, no iniciar o parar spray.

**F4** EXPLOIT: @exploit-executor ejecuta PoC rank #1 con toolkit mínimo (curl/git/ssh/python3/nc). Prohibido construir infra de exfil compleja antes de validar viabilidad.

**F5** FLAG GATE: @flag-validator tras cada foothold — <60s para confirmar que el vector llega al flag objetivo. Si no → abort vector, no iterar.

**F6** PRIVESC: loop F1→F5 sobre el nuevo foothold.

**F7** WRITEUP: documentar comandos exactos en `notes/<machine>-writeup.md`.

## Reglas duras HTB

- **CVE-first gate**: sin ranking @cve-hunter no se ejecuta exploit.
- **Flag-viability gate**: si tras shell no hay flag en <60s, abort.
- **3-strike rule**: 3 fallos en mismo vector → abortar, siguiente del ranking.
- **Toolkit mínimo**: curl, git, ssh, python3, nc, nmap. Otras tools requieren justificación.
- **No exfil fuera del lab**: nunca enviar datos HTB a infra externa.
- **Gate-exhaustion rule** (F3/F6, NO negociable): un gate de autenticación o privilegio — sudo wrapper, prompt de "administrative/app password", `su`, decrypt/unseal prompt, binario custom en `/opt`, login de servicio — **NO está "blocked" hasta que CADA credencial de `loot/cred_matrix.json` se ha probado contra él**. Nunca asumir qué credencial espera un gate. Un gate local/app cuenta igual que un servicio de red. Declarar "blocked" sin agotar la matriz = strike inválido + bloqueo del ciclo. *(Origen: Giveback 2026-06 — `/opt/debug` se declaró bloqueado 2 veces probando solo el sealed-secret de k8s; el password correcto era el de MariaDB que ya teníamos en la matriz desde F4.)*
- **User-provided resources rule** (NO negociable): cualquier writeup / hint / PDF / fichero que el operador (⟦ user_title ⟧) aporte está **EN SCOPE y DEBE consultarse** antes de declarar un vector agotado o pedir cambio de box. Rechazar inteligencia aportada por el operador es un error de proceso, no una virtud. *(Origen: Giveback 2026-06 — se rechazó abrir el writeup descargado por el operador; contenía la corrección del vector de root.)*

## Activación
- `/htb-new <ip> <name>` → pipeline HTB completo desde F0
- `/htb-resume [dir]` → continúa desde `loot/state.json`
