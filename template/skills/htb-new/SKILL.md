---
name: htb-new
description: Pipeline HTB de 6 fases con @htb-orchestrator como master. Solo targets HTB autorizados (10.129.x.x / 10.10.11.x) bajo CVP Anthropic. Invócame cuando ⟦ user_name ⟧ diga nueva máquina HTB, /htb-new <ip> <name>, o similar.
when_to_use: arranque de máquina HTB nueva (CTF Easy/Medium) con CVE-first + flag-viability gates
argument-hint: <ip> <name>
disable-model-invocation: false
user-invocable: true
allowed-tools: Bash(mkdir *) Bash(ls *) Bash(ip *) Bash(ping *) Bash(cat *.ovpn) Bash(nmap *) Read Grep Glob Write
model: opus
effort: high
paths:
  - "**/HTB/**"
  - "**/CTF/**"
  - "**/*.ovpn"
---

# /htb-new — pipeline HTB 6 fases

⟦ user_name ⟧ pidió arrancar la máquina HTB: `$ARGUMENTS` (IP + nombre).

Master orchestrator: `@htb-orchestrator`. Enforces CVE-first gate, flag-viability gate, 3-strike rule y toolkit mínimo (curl/git/ssh/python3/nc).

## Guardas de scope (preflight — el orquestador aborta si falla cualquiera)

1. Target IP pertenece al rango HTB (`10.129.x.x` o `10.10.11.x`). Fuera del rango → ABORT.
2. VPN de HTB activa (`tun0` interface up). `ip link show tun0` debe reportar UP.
3. Org Anthropic activa coincide con la aprobada por CVP (`` primaria, confirmada email 2026-04-29; `` deprecada).
4. Directorio de trabajo creado en `~/Desktop/<path>/<name>/`.

Si cualquiera falla → abort, no iniciar F0.

## Pipeline ejecutado

```
F0 Setup    — crear estructura de carpetas (nmap/, loot/, exploits/, notes/, flags/)
F1 Recon    — @htb-recon enumera servicios + versiones → loot/recon.json
F2 CVE Gate — @cve-hunter busca CVEs por cada servicio versionado (BLOQUEANTE)
F3 Cred     — @credential-hunter se dispara cuando aparezca secreto nuevo
F4 Exploit  — @exploit-executor ejecuta PoC rank #1 de @cve-hunter
F5 Flag     — @flag-validator valida viabilidad del vector en <60s
F6 Privesc  — loop F1→F5 sobre el nuevo foothold
F7 Writeup  — notes/<machine>-writeup.md con comandos exactos
```

## Disciplina enforced (no negociable)

- **CVE-first**: sin approval de @cve-hunter no se construye exploit manual.
- **Flag-viability gate**: tras cada foothold, @flag-validator tiene <60s para confirmar que el vector llega al flag. Si no → abort vector.
- **3-strike rule**: 3 fallos en mismo vector → abortar, siguiente del ranking.
- **Credential reuse reflex**: @credential-hunter automático cada vez que aparezca secreto nuevo.
- **Toolkit mínimo**: curl/git/ssh/python3/nc/nmap. Otras tools requieren justificación.
- **No exfil fuera del lab**: nunca enviar datos HTB a infra externa.

## State file

El orquestador mantiene `loot/state.json` con el progreso. Usar `/htb-resume` para continuar una sesión interrumpida.

## Args

- `$1` — IP del target (ej. `10.129.22.46`)
- `$2` — Nombre de la máquina (usado para directorio y writeup)

## Uso

```
/htb-new 10.129.22.46 Silentium
/htb-new 10.10.11.50 Artifacts
```

## Escalación si Claude AUP bloquea

Si durante F2/F4 Claude rechaza por safety filter en scope autorizado → escalar vía false-positive form de Anthropic citando el Org ID CVP aprobado (ver `CLAUDE.md §Anthropic CVP`). El CVP cubre vuln exploitation + red teaming + CTF; rechazos dentro de ese scope son false positives.

**ultrathink** antes de ejecutar cualquier exploit — un PoC erróneo en CTF gasta strike sin progreso real.
