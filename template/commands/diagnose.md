---
description: Diagnóstico completo del proyecto. Estructura, dependencias, issues potenciales.
allowed-tools: Read, Bash(eza *), Bash(fd *), Bash(rg *), Bash(bat *), Bash(git *)
---

Realiza un diagnóstico completo del proyecto actual:

## 1. Estructura
```bash
eza --tree -L 3 --git-ignore
```

## 2. Dependencias
- Buscar pyproject.toml, package.json, Cargo.toml, go.mod
- Verificar lockfiles presentes
- Detectar dependencias desactualizadas

## 3. Configuración
- Git configurado correctamente
- .gitignore presente y completo
- CI/CD configurado
- Pre-commit hooks

## 4. Código
- Estructura de directorios
- Tests presentes
- Documentación
- Tipos/interfaces definidos

## 5. Seguridad
- Secrets en .env (no commiteado)
- No credentials hardcodeadas
- Dependencias sin vulnerabilidades conocidas

## Output
Genera reporte con:
- [PASS] Bien configurado
- [WARN] Mejorable
- [FAIL] Problema detectado
- [NOTE] Recomendaciones priorizadas
