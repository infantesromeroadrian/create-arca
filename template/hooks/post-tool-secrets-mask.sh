#!/bin/bash
# ARCA — PostToolUse secrets-mask (Claude Code 2.1.121+)
#
# Inspects tool output AFTER execution and masks obvious credential
# patterns before they land in the conversation. Defense-in-depth:
# block-dangerous.sh and detect-secrets.sh prevent us from WRITING
# secrets out; this hook prevents reading them BACK from a Bash/Read
# output into context where the assistant might later echo them.
#
# ADR-108 v2 (2026-06-18): now sources lib/secret-patterns.sh (single
# source of truth), covers [Bash|Read] matchers, and writes a session
# leak flag consumed by persistence hooks (engram-snapshot-on-stop,
# obsidian-session-close, repo-mirror-sync) to redact-mark or skip
# persisting the contaminated turn.
#
# Returns Claude Code's hookSpecificOutput.updatedToolOutput on stdout
# only when something was masked. Otherwise prints nothing.

set -uo pipefail

# Source canonical pattern catalog (ADR-108).
# shellcheck source=lib/secret-patterns.sh
source "${HOME}/.claude/hooks/lib/secret-patterns.sh"

LOG="${HOME}/.claude/state/secrets-mask.log"
BRIEFING_DIR="${HOME}/.claude/briefing"
mkdir -p "$(dirname "$LOG")" "${BRIEFING_DIR}" 2>/dev/null || true

input="$(cat 2>/dev/null || true)"
[[ -z "$input" ]] && exit 0

original="$(printf '%s' "$input" | jq -r '.tool_response.output // .tool_response // .tool_response.content // ""' 2>/dev/null)"
[[ -z "$original" ]] && exit 0

session_id="$(printf '%s' "$input" | jq -r '.session_id // "unknown"' 2>/dev/null)"
tool_name="$(printf '%s' "$input" | jq -r '.tool_name // "?"' 2>/dev/null)"
file_path="$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.path // ""' 2>/dev/null)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null)"

masked="$original"
hits=0
labels=""

apply_pattern() {
    local label="$1" regex="$2"
    local before="$masked"
    masked="$(printf '%s' "$masked" | sed -E "s@${regex}@[MASKED:${label}]@g")"
    if [[ "$masked" != "$before" ]]; then
        hits=$((hits + 1))
        labels="${labels:+$labels,}${label}"
    fi
}

for entry in "${SECRET_PATTERNS_ABSOLUTE[@]}"; do
    label="${entry%%|*}"; regex="${entry#*|}"
    apply_pattern "$label" "$regex"
done

for entry in "${SECRET_PATTERNS_STANDARD[@]}"; do
    label="${entry%%|*}"; regex="${entry#*|}"
    apply_pattern "$label" "$regex"
done

if (( hits > 0 )); then
    # Structured log entry (extended with session + labels).
    printf '%s | session=%s | tool=%s | masked=%d | labels=%s | preview=%s\n' \
        "$(date -Iseconds)" "$session_id" "$tool_name" "$hits" "$labels" \
        "$(printf '%s' "$original" | head -c 80 | tr '\n' ' ')" >> "$LOG"

    # ADR-108 D1: session leak flag (plain text, append-style; no JSON state).
    # Persistence hooks check existence of this file to skip/redact sessions.
    flag="${BRIEFING_DIR}/${session_id}.leak"
    if [[ ! -f "$flag" ]]; then
        {
            printf 'first_leak=%s\n' "$(date -Iseconds)"
            printf 'session=%s\n' "$session_id"
        } > "$flag"
        chmod 600 "$flag"
    fi
    # Append every leak (audit trail). Persistence hooks only need existence check.
    printf 'leak ts=%s tool=%s hits=%d labels=%s file=%s cmd=%s\n' \
        "$(date -Iseconds)" "$tool_name" "$hits" "$labels" "$file_path" "$cmd" >> "$flag"

    # Stderr warning visible to ARCA (not to stdout, which would pollute the mask).
    printf '[secret-leak-detector] POST %s masked=%d labels=%s session=%s flag=%s\n' \
        "$tool_name" "$hits" "$labels" "$session_id" "$flag" >&2

    # Emit masked output via Claude Code's hookSpecificOutput contract.
    jq -nc --arg out "$masked" '{
        hookSpecificOutput: {
            hookEventName: "PostToolUse",
            updatedToolOutput: $out
        }
    }'
fi
exit 0
