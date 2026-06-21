#!/bin/bash
# block-sensitive-reads.sh — PreToolUse gate for sensitive-path reads (ADR-108 D2).
#
# WHY: detect-secrets.sh is content-based; it cannot catch a `cat` on a file with
# token-shaped names but no regex-matchable command (e.g.
# `cat ~/.config/opencode/opencode.json`). This hook is path-based — it denies
# reads on a small denylist of well-known secret-bearing files UNLESS the operator
# has explicitly allowlisted them for a CTF/lab context.
#
# Block semantics: exit 2 = block. The agent must either request operator approval
# via the `question` tool, OR use scripts/redact-cat.sh which masks known patterns
# before the content reaches the model.
#
# Matcher (settings.json): PreToolUse on [Bash|Read].

set -uo pipefail

input="$(cat 2>/dev/null || true)"
[[ -z "$input" ]] && exit 0

tool_name="$(printf '%s' "$input" | jq -r '.tool_name // ""' 2>/dev/null)"

# Extract target path depending on tool shape.
target=""
case "$tool_name" in
    Read)
        target="$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.path // ""' 2>/dev/null)"
        ;;
    Bash)
        # Inspect the command for cat/less/head/tail on a sensitive path.
        # Conservative: only block direct file reads; ignore pipelines/grep/etc.
        cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null)"
        # Match: cat|head|tail|less|more|vi|vim|nano <path>
        if printf '%s' "$cmd" | grep -qE '^\s*(cat|head|tail|less|more|view|vim|vi|nano)\s+([^|;&]+\s*)+$'; then
            target="$(printf '%s' "$cmd" | awk '{print $NF}' | sed -E 's/^["'\'']//; s/["'\'']$//')"
        fi
        ;;
esac

[[ -z "$target" ]] && exit 0

# Normalize ~ and relative paths.
target="${target/#\~/$HOME}"

# Convert to absolute for matching.
target_abs="$(readlink -f "$target" 2>/dev/null || echo "$target")"

# Sensitive paths denylist (extended from ADR-108 D2).
is_sensitive=false
for pattern in \
    "${HOME}/.config/opencode/opencode.json" \
    "${HOME}/.aws/credentials" \
    "${HOME}/.aws/config" \
    "${HOME}/.kube/config" \
    "${HOME}/.netrc" \
    "${HOME}/.docker/config.json" \
    "${HOME}/.config/opencode/opencode.json.bak"
do
    [[ "$target_abs" == "$pattern" ]] && is_sensitive=true && break
done

# Glob patterns (private keys, .env).
[[ "$target_abs" == "${HOME}/.ssh/id_"* ]] && is_sensitive=true
[[ "$target_abs" == *"/.env" ]] && is_sensitive=true
[[ "$target_abs" == *"/.env.local" ]] && is_sensitive=true
[[ "$target_abs" == *"/secrets.json" ]] && is_sensitive=true
[[ "$target_abs" == *"/credentials.json" ]] && is_sensitive=true
# .env.example and .env.template are intentionally NOT denied.

# GnuPG directory.
[[ "$target_abs" == "${HOME}/.gnupg"/* ]] && is_sensitive=true

if [[ "$is_sensitive" != "true" ]]; then
    exit 0
fi

# Operator allowlist (CTF/lab exceptions).
allowlist="${HOME}/.claude/hooks/lib/sensitive-paths.allowlist"
if [[ -f "$allowlist" ]]; then
    while IFS= read -r line; do
        # Skip comments and empties.
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        norm="${line/#\~/$HOME}"
        [[ "$target_abs" == "$norm" ]] && exit 0
    done < "$allowlist"
fi

# Block.
cat >&2 <<MSG
[block-sensitive-reads] DENIED read on sensitive path: $target_abs

This file is on the ADR-108 D2 denylist (live secrets). To proceed, either:

  1. Use the redacting reader:  bash ${HOME}/.claude/scripts/redact-cat.sh "$target_abs"
     (returns the file with all known token patterns masked).

  2. Ask the operator via the question tool for explicit one-shot approval.

  3. Add the path to ${allowlist} for a CTF/lab context
     (remember to remove the entry when done).

Block event: tool=$tool_name session=$(printf '%s' "$input" | jq -r '.session_id // "unknown"')
MSG
exit 2
