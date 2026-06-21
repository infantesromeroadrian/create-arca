---
name: htb-methodology
description: Metodología Codex-style para resolver HTB Easy/Medium. Árbol de decisión CVE-first, patrones de reconocimiento, lista de falsos positivos comunes, economía de herramientas. Cargar en cualquier agente del pipeline HTB.
paths:
  - "**/HTB/**"
  - "**/loot/**"
---

# HTB Methodology — Codex-style

Este skill codifica la metodología que resuelve HTB Easy/Medium más rápido: patrón conocido → solución conocida. No research, no originalidad, toolkit mínimo.

## Árbol de decisión maestro

```
Dado un servicio descubierto con versión conocida:

  1. ¿Hay CVE pública con PoC funcional para esta versión exacta?
     SÍ → Aplicar CVE (siempre antes que cualquier otra cosa)
     NO → siguiente paso

  2. ¿El servicio expone endpoint obvio de credenciales / misconfig?
     (forgot-password leaking token, env vars, debug endpoint, /config)
     SÍ → Extraer → @credential-hunter con pool ampliado
     NO → siguiente paso

  3. ¿Hay indicios de credenciales por defecto / triviales?
     (usuarios visibles: "admin", "hacker", "test", "dev")
     SÍ → Probar Hacker123!, admin, password, <user>, <user>123
     NO → siguiente paso

  4. ¿Hay config leak readable? (/etc/<app>.conf, .env, app.ini)
     SÍ → Buscar SECRET_KEY, JWT_SECRET, passwords hardcoded
     NO → siguiente paso

  5. Vector manual: SSRF / LFI / IDOR / XXE / SSTI básico
     Aplicar playbook de la bug class.
```

## Patrones HTB Easy/Medium confirmados

### Patrón "credencial reuse cross-service"
Si un servicio expone `SMTP_PASSWORD`, `DB_PASSWORD`, o similar → probar como SSH password del usuario admin. Tasa de éxito >70% en HTB Easy.

### Patrón "servicio antiguo + root"
Si ves `Gogs 0.13.x`, `Gitea < 1.20`, `Jenkins < 2.30`, `Flowise < 3.1` corriendo como root o con repos en `/root/...` → 90% probable CVE conocida con escalada a root.

### Patrón "Docker container NO es el flag"
RCE en contenedor Docker **casi nunca** lleva al flag directamente. El flag está en el host. Buscar otro vector que corra en el host.

Excepción: container privilegiado o con `/host` mount. Verificar `mount | grep host`.

### Patrón "primer usuario = admin"
En Gogs/Gitea/Jenkins, el primer usuario registrado es admin por defecto. Si `INSTALL_LOCK=true` y ya hay usuarios → el admin probablemente es UID 1 y tiene nombre predecible (dueño del nombre de la máquina, "admin", o el usuario SSH).

### Patrón "API key > JWT"
Si el servicio tiene tanto JWT (stateful, revocable) como API key (estático) → la API key suele seguir viva aunque el JWT haya caducado. Buscarla en endpoints `/api/v1/apikey`, `/user/settings/applications`.

## Falsos positivos comunes (NO perseguir)

### FP: Puerto filtered en nmap
`filtered` NO significa cerrado. A veces es firewall con drop. Reconfirmar con `-sS` o `-sU`. Pero no inviertas más de 5 min — si sigue filtered, asumir cerrado.

### FP: RCE en container aislado
Ver "Patrón Docker" arriba. Si el flag no está en el container filesystem ni en mounts visibles → drop the vector.

### FP: JWT forgery cuando la app usa stateful sessions
Si cada JWT tiene un `meta` field con nonce/hash que se valida contra DB → no puedes forjar uno válido aunque tengas el secret. Abort el approach.

### FP: SQL injection en búsqueda que devuelve 200 siempre
Si `?q=1' OR '1'='1` devuelve mismo número de resultados que `?q=1`, puede ser WAF absorbiendo la comilla. Mirar diffing real, no solo status codes.

### FP: Admin panel a `/admin`
`/admin` devolviendo `403 Forbidden` significa "existe pero no tienes acceso". NO es una vía de entrada por sí sola.

### FP: /etc/passwd readable via LFI
Muy común pero raramente útil. `passwd` no tiene hashes modernos. Lo útil es `/etc/shadow` (requiere root para leer) o `id_rsa`/`.ssh/` de usuarios.

## Economía de herramientas

### Toolkit HTB por defecto
```
curl    — 80% de las acciones HTTP
git     — clone + symlink + push tricks
ssh     — auth + -L/-R forwarding
python3 -c "..."  — JSON payloads, base64, JWT generation
nc      — listener simple para reverse shell (último recurso)
hydra   — brute force SSH/HTTP (controlado)
ffuf    — vhost / dir enum
searchsploit — CVE lookup offline
```

### Cuándo NO usar más herramientas
- Listeners Python HTTP: solo si necesitas servir archivos al target (SSRF → file). Para reverse shells basta `nc`.
- Base64 chains: solo si el target no soporta binary data en el output. Antes de encadenar 3 base64, prueba sin ninguno.
- Docker / Kubernetes tools: nunca en HTB. Si piensas "voy a meter un container" → estás sobre-ingenierizando.
- Metasploit: sólo si el CVE tiene módulo oficial y el PoC manual es demasiado complejo.

## Lectura literal del target

**Si ves esto en la app → significa exactamente esto:**

| Señal | Significado |
|---|---|
| Usuarios `admin`, `hacker`, `test` visibles | Password trivial probable |
| `RUN_USER=root` en config | Todo lo que ese servicio ejecuta corre como root |
| `repos/` bajo `/root/` | Git hooks / repo manipulation → root |
| Docker con volumen `/var/run/docker.sock` | Container escape por socket |
| `.env` filtrado con SMTP creds | Cross-service password reuse inmediato |
| Endpoint `/forgot-password` en app con SMTP deshabilitado | Token probablemente devuelto en respuesta |

## Disciplina de iteración

### Regla de 3 strikes
Si un vector falla 3 veces → abort y cambiar. No iterar una cuarta vez.

### Regla de 60 segundos post-foothold
Tras conseguir shell/RCE, tienes 60s para validar que llegas al flag. Si no, el vector no sirve — siguiente.

### Regla de precedencia
```
CVE pública    >  credencial reuse   >  config leak   >   exploit manual
Toolkit mínimo >  tooling custom     >  frameworks    >   Metasploit
Lectura literal > interpretación     >  hipótesis     >   teorización
```

## Estructura de proyecto HTB recomendada

```
<machine>/
├── nmap/                 # scans de @htb-recon
│   ├── full-tcp.txt
│   └── scripts.txt
├── loot/                 # artefactos extraídos
│   ├── recon.json        # output de @htb-recon
│   ├── cves_<svc>.json   # output de @cve-hunter por servicio
│   ├── cred_matrix.json  # output de @credential-hunter
│   └── state.json        # estado del orquestador
├── exploits/             # PoCs ejecutados
│   └── CVE-XXXX/         # uno por CVE
├── notes/
│   └── <machine>-writeup.md  # documentar al terminar
└── flags/
    ├── user.txt
    └── root.txt
```
