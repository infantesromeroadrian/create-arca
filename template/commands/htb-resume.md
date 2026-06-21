---
description: Continúa pipeline HTB desde el último estado guardado en loot/state.json. Uso, /htb-resume [machine-directory]. Si no se pasa directorio, usa el CWD actual.
---

# /htb-resume — Continuar pipeline HTB

Reanuda una sesión HTB interrumpida leyendo `loot/state.json` y delegando a `@htb-orchestrator` con el contexto recuperado.

## Usage

```
/htb-resume                          # usa CWD actual
/htb-resume ~/Desktop/.../Silentium   # directorio explícito
```

## Precondiciones

1. Existe `<dir>/loot/state.json` con estructura válida.
2. VPN HTB sigue activa (tun0 up).
3. Target aún está accesible (ping rápido antes de continuar).

## Qué hace

1. Lee `loot/state.json` → recupera fase actual, foothold activo, vectores probados/abortados, secretos.
2. Lee `loot/recon.json`, `loot/cves_*.json`, `loot/cred_matrix.json` → contexto completo.
3. Lee `notes/<machine>-writeup.md` si existe → comandos ya ejecutados.
4. Entrega todo al `@htb-orchestrator` con directiva: "continúa desde F<x>".

## Qué NO hace

- NO re-ejecuta recon si ya existe `loot/recon.json` (< 24h).
- NO re-busca CVEs si ya existe `loot/cves_*.json` (< 7 días).
- NO re-prueba credenciales que ya están en `cred_matrix.json` como miss.
- NO repite vectores marcados en `vectors_aborted` sin razón justificada (ej. nueva CVE disponible).

## Fallback

Si el state está corrupto o incompleto → ofrecer `/htb-new` desde cero y archivar el state actual a `loot/state.json.bak`.

## Args

- `$1` (opcional) — path al directorio de la máquina. Default: CWD.
