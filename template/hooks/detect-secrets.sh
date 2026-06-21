#!/bin/bash
# PreToolUse hook — secret scanner consolidado.
# Unifica detect-secrets.sh + pii_check.sh (v2.0).
# Bloquea secrets en writes/edits. Whitelist para paths educativos (CVP Anthropic scope).

set -euo pipefail

INPUT=$(cat)
CONTENT=$(echo "$INPUT" | jq -r '.tool_input.content // .tool_input.new_string // empty' 2>/dev/null || echo "")
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null || echo "")

[[ -z "$CONTENT" ]] && exit 0

# === Skip .env and .env.local / .env.example / .env.template ===
FILENAME=$(basename "$FILE_PATH" 2>/dev/null || echo "")
if echo "$FILENAME" | grep -qE '^\.env(\.local|\.example|\.template)?$'; then
  exit 0
fi

# === Educational / CTF whitelist (CVP Anthropic scope) ===
# HTB Academy, red-teaming labs, bug-bounty notebooks pueden contener tokens
# dummy y credenciales de ejemplo con proposito pedagogico.
EDUCATIONAL_PATH=false
if echo "$FILE_PATH" | grep -qiE '(/|^)(HTB|Academy|AI-Red-Teaming|red-teaming|red_teaming|CTF|htb-academy|ctf-notebooks|ctf_notebooks|bug-bounty|pentesting-labs)(/|$)'; then
  EDUCATIONAL_PATH=true
fi

# =============================================================================
# PATRONES ABSOLUTOS — bloquean SIEMPRE, incluso en paths educativos
# =============================================================================

# AWS access keys (prefix AKIA es AWS-specific, nunca legitimo en docs)
if echo "$CONTENT" | grep -qE 'AKIA[0-9A-Z]{16}'; then
  echo "BLOCKED: AWS access key detected in $FILE_PATH" >&2; exit 2
fi

# Private keys (todos los tipos: RSA/DSA/EC/OPENSSH/PGP)
if echo "$CONTENT" | grep -qE 'BEGIN[[:space:]]+(RSA|DSA|EC|OPENSSH|PGP)?[[:space:]]*PRIVATE[[:space:]]+KEY'; then
  echo "BLOCKED: private key detected in $FILE_PATH" >&2; exit 2
fi

# =============================================================================
# Skip resto de checks si path educativo (tokens de ejemplo son OK ahi)
# =============================================================================
if [[ "$EDUCATIONAL_PATH" == true ]]; then
  exit 0
fi

# =============================================================================
# Token prefixes conocidos (service-specific, low false positive)
# =============================================================================

# Anthropic specific (sk-ant-api/oat)
if echo "$CONTENT" | grep -qE 'sk-ant-(api|oat)[0-9]{2,}-[A-Za-z0-9_-]{20,}'; then
  echo "BLOCKED: Anthropic API key detected in $FILE_PATH" >&2; exit 2
fi

# OpenAI (sk-) generic
if echo "$CONTENT" | grep -qE 'sk-[a-zA-Z0-9]{20,}'; then
  echo "BLOCKED: sk- API token detected in $FILE_PATH" >&2; exit 2
fi

# NVIDIA
if echo "$CONTENT" | grep -qE 'nvapi-[a-zA-Z0-9_-]{20,}'; then
  echo "BLOCKED: NVIDIA API token detected in $FILE_PATH" >&2; exit 2
fi

# Hugging Face
if echo "$CONTENT" | grep -qE 'hf_[a-zA-Z0-9]{20,}'; then
  echo "BLOCKED: Hugging Face token detected in $FILE_PATH" >&2; exit 2
fi

# GitHub tokens (ghp_, gho_, ghu_, ghs_, ghr_)
if echo "$CONTENT" | grep -qE 'gh[pousr]_[A-Za-z0-9]{36,}'; then
  echo "BLOCKED: GitHub token detected in $FILE_PATH" >&2; exit 2
fi

# Slack tokens (xox[bpoa]-)
if echo "$CONTENT" | grep -qE 'xox[bpoa]-[A-Za-z0-9-]{30,}'; then
  echo "BLOCKED: Slack token detected in $FILE_PATH" >&2; exit 2
fi

# Google API keys (AIza prefix)
if echo "$CONTENT" | grep -qE 'AIza[0-9A-Za-z_-]{35}'; then
  echo "BLOCKED: Google API key detected in $FILE_PATH" >&2; exit 2
fi

# Google OAuth (ya29.)
if echo "$CONTENT" | grep -qE 'ya29\.[0-9A-Za-z_-]{20,}'; then
  echo "BLOCKED: Google OAuth token detected in $FILE_PATH" >&2; exit 2
fi

# LangSmith (lsv2_pt_/sk_)
if echo "$CONTENT" | grep -qE 'lsv2_(pt|sk)_[a-f0-9]{32}_[a-f0-9]{10}'; then
  echo "BLOCKED: LangSmith API key detected in $FILE_PATH" >&2; exit 2
fi

# JWT tokens (3 base64 segments separated by dots)
if echo "$CONTENT" | grep -qE 'eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}'; then
  echo "BLOCKED: JWT token detected in $FILE_PATH" >&2; exit 2
fi

# Bearer tokens
if echo "$CONTENT" | grep -qE '[Bb]earer[[:space:]]+[A-Za-z0-9_-]{20,}'; then
  echo "BLOCKED: Bearer token detected in $FILE_PATH" >&2; exit 2
fi

# =============================================================================
# Patrones genericos (higher false positive rate, last resort)
# =============================================================================

# Generic API keys / tokens (long strings assigned to key-like vars)
if echo "$CONTENT" | grep -qiE '(api[_-]?key|api[_-]?token|secret[_-]?key|access[_-]?token|auth[_-]?token|access[_-]?key)[[:space:]]*[:=][[:space:]]*["'"'"'][A-Za-z0-9+/=_-]{20,}'; then
  echo "BLOCKED: hardcoded API key/token detected in $FILE_PATH" >&2; exit 2
fi

# Passwords in key=value format
if echo "$CONTENT" | grep -qiE '(password|passwd|pwd)[[:space:]]*[:=][[:space:]]*["'"'"'][^"'"'"']{4,}'; then
  echo "BLOCKED: hardcoded password detected in $FILE_PATH" >&2; exit 2
fi

# Passwords in connection URLs (proto://user:pass@host)
if echo "$CONTENT" | grep -qiE '://[^:]+:[^@]{4,}@'; then
  echo "BLOCKED: password in connection URL detected in $FILE_PATH" >&2; exit 2
fi

exit 0
