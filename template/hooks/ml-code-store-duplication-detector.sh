#!/usr/bin/env bash
# ml-code-store-duplication-detector.sh
#
# PostToolUse:Edit|Write|MultiEdit advisory hook (ADR-026).
#
# When code is written to <project>/src/, scan <project>/ml-code-store/
# for high-similarity functions. If similarity >80% on any defined
# function name, emit an advisory stderr nudge inviting reuse.
#
# Advisory only. Exit 0 always. Never blocks Claude.
# ⟦ user_name ⟧'s preference (2026-05-04): "lo que menos rompa claude".
#
# Detection method (cheap, deterministic):
# 1. Extract function/class names from the new file (Python def/class).
# 2. For each, glob ml-code-store/ for files defining the same name.
# 3. If found, emit advisory citing the existing path and suggest reuse.
#
# Skipped when:
# - File is not under <project>/src/.
# - Project has no ml-code-store/ directory yet.
# - File has zero def/class declarations.
#
# State: none. Stateless on purpose — re-runs on every Edit/Write.

set -euo pipefail

# Read PostToolUse JSON from stdin.
INPUT="$(cat)"

# Extract file path from the tool input. Supports Edit/Write/MultiEdit.
FILE_PATH="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty')"

# Bail silently if no path or path not under src/.
if [[ -z "$FILE_PATH" ]] || [[ ! "$FILE_PATH" =~ /src/ ]]; then
  exit 0
fi

# Find project root (closest ancestor containing ml-code-store/).
PROJECT_ROOT=""
DIR="$(dirname "$FILE_PATH")"
while [[ "$DIR" != "/" ]]; do
  if [[ -d "$DIR/ml-code-store" ]]; then
    PROJECT_ROOT="$DIR"
    break
  fi
  DIR="$(dirname "$DIR")"
done

# No store in any ancestor → silent exit.
if [[ -z "$PROJECT_ROOT" ]]; then
  exit 0
fi

STORE_DIR="$PROJECT_ROOT/ml-code-store"

# Only handle Python for now. Other languages: future work.
if [[ ! "$FILE_PATH" =~ \.py$ ]]; then
  exit 0
fi

# File must exist and be readable.
if [[ ! -r "$FILE_PATH" ]]; then
  exit 0
fi

# Extract def/class names from the new file.
# grep -oP because Python identifiers are predictable.
NAMES="$(grep -oP '^\s*(def|class)\s+\K[a-zA-Z_][a-zA-Z0-9_]*' "$FILE_PATH" 2>/dev/null | sort -u || true)"

if [[ -z "$NAMES" ]]; then
  exit 0
fi

# Check each name against the store.
HITS=()
while IFS= read -r NAME; do
  [[ -z "$NAME" ]] && continue
  # Skip private/dunder.
  [[ "$NAME" =~ ^_ ]] && continue
  # Search store for same identifier as def/class.
  MATCHES="$(grep -rlE "^\s*(def|class)\s+${NAME}\b" "$STORE_DIR" 2>/dev/null || true)"
  if [[ -n "$MATCHES" ]]; then
    while IFS= read -r MATCH; do
      [[ -z "$MATCH" ]] && continue
      REL="${MATCH#$PROJECT_ROOT/}"
      HITS+=("$NAME -> $REL")
    done <<< "$MATCHES"
  fi
done <<< "$NAMES"

# Emit advisory if any hits, then exit 0.
if [[ ${#HITS[@]} -gt 0 ]]; then
  {
    printf '\n[ml-code-store advisory] possible reuse opportunity in %s:\n' "$FILE_PATH"
    for HIT in "${HITS[@]}"; do
      printf '  - %s\n' "$HIT"
    done
    printf 'Consider importing from ml-code-store/ instead of redefining. '
    printf '@maintainability-engineer will flag this in the next gate (ADR-026).\n\n'
  } >&2
fi

exit 0
