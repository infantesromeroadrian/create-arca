---
description: Inicia pipeline HTB completo con @htb-orchestrator. Uso, /htb-new <ip> <name>. Solo targets HTB autorizados (10.129.x.x / 10.10.11.x) bajo CVP de Anthropic.
---

# /htb-new — Pipeline HTB

Arranca el pipeline HTB de 6 fases con `@htb-orchestrator` como master.

## Usage

```
/htb-new 10.129.22.46 Silentium
/htb-new 10.10.11.50 Artifacts
```

## Precondiciones (verificadas por el orquestador)

1. Target IP pertenece al rango HTB (`10.129.x.x` o `10.10.11.x`).
2. VPN de HTB activa (`tun0` interface up).
3. Org Anthropic activa coincide con la aprobada por CVP.
4. Directorio de trabajo creado en `~/Desktop/<path>/<name>/`.

Si cualquiera falla → abort.

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

## Disciplina enforced

- CVE-first (sin approval de @cve-hunter no se construye exploit manual)
- Flag-viability gate tras cada foothold
- 3-strike rule por vector
- Credential reuse reflex automático
- Toolkit mínimo: curl/git/ssh/python3/nc

## State file

El orquestador mantiene `loot/state.json` con el progreso. Usar `/htb-resume` para continuar una sesión interrumpida.

## Args

- `$1` — IP del target
- `$2` — Nombre de la máquina (usado para directorio y writeup)
