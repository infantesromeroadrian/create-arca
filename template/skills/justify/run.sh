#!/bin/bash
# ARCA — /justify slash command runner (ARCA-SEC-1 hardened).
#
# Reads the user's justification text from stdin (NOT from argv, NOT from
# environment, NOT from $ARGUMENTS interpolation). The slash command in
# commands/justify.md feeds this script via a single-quoted heredoc, which
# bash refuses to expand. That removes the command-injection vector that
# existed in the previous in-line bash block, where `TEXT="$ARGUMENTS"`
# allowed `$(...)` and backtick payloads inside the user input to execute
# during the assignment.
#
# Why stdin and not argv: even `bash run.sh "$ARGUMENTS"` is unsafe,
# because Claude Code substitutes $ARGUMENTS textually before bash parses
# the line, so a payload like `x-$(touch /tmp/PWN)-y` still reaches the
# shell parser inside double quotes and gets executed. A heredoc whose
# delimiter is single-quoted (<<'EOF') is the only literal-text channel
# bash provides.
#
# Contract:
#   stdin  — UTF-8 justification text, may contain any bytes
#   argv   — none accepted; any positional arg triggers exit 2
#   stdout — single human-readable confirmation line on success
#   stderr — rejection reason on validation failure
#   exit 0 — accepted, state file written
#   exit 1 — rejected by content rule (too short, reserved tokens)
#   exit 2 — environment / safety failure: argv non-empty, jq missing,
#            state dir not writable, SESSION_ID fails whitelist
#
# State file format:
#   $HOME/.claude/state/current-justification.json
#   { justification, created_at (epoch s), ttl_seconds, consumed }
#
# Why a single file (no session_id in the path): the previous layout
# stored each justify under <session_id>.json. The hook side
# (forced-justification.sh) reads session_id from the runtime stdin JSON,
# while this script can only resolve it from CLAUDE_SESSION_ID (NOT
# exported by the runtime to skill scripts as of Claude Code docs
# 2026-05-01 — confirmed via claude-code-guide audit) or the on-disk
# current-session-id marker (updated by session-id-marker.sh on
# UserPromptSubmit, with windows of staleness across subagents and
# prompt boundaries). The two paths desynced and the hook ended up
# reading the wrong file. A single canonical state file removes the
# entire class of session-id desync bugs.
#
# Multi-process isolation (resolved via Option B, 2026-05-02):
#   The state path is now keyed by the ancestor `claude` PID resolved
#   via hooks/lib/claude-process-id.sh. Both this script and the
#   forced-justification.sh hook share the same ancestor when running
#   inside the same claude session, so they hit the same file. Multiple
#   concurrent claude processes (parallel worktrees, multiple terminals)
#   get isolated state files and no longer overwrite each other. The
#   previously-documented Option C limitation is closed.

set -uo pipefail

# Reserved channel: this script reads exclusively from stdin. Any positional
# arg is a sign the caller has either (a) regressed to the pre-hardening
# argv pattern or (b) widened allowed-tools so a future caller could pass
# attacker-controlled bytes via argv. Reject loudly. ARCA-SEC-1.
if [[ $# -gt 0 ]]; then
    echo "[/justify] ENTORNO: este script no acepta argumentos posicionales (ARCA-SEC-1, ADR-007)." >&2
    exit 2
fi

readonly MIN_CHARS=20
readonly TTL_SECONDS=120
readonly STATE_DIR="${HOME}/.claude/state"
# Per-claude-process state path. Walk the process tree to find the
# `claude` ancestor PID and key the state file by it. Both this script
# and forced-justification.sh share the same ancestor when running
# inside the same claude session, so they resolve to the same file.
# Multiple concurrent `claude` processes get isolated state.
CLAUDE_PID=$(bash "${HOME}/.claude/hooks/lib/claude-process-id.sh" 2>/dev/null || echo "")
if [[ -n "$CLAUDE_PID" ]]; then
    STATE_FILE="${STATE_DIR}/current-justification-${CLAUDE_PID}.json"
else
    STATE_FILE="${STATE_DIR}/current-justification.json"
fi
readonly STATE_FILE

# Read everything stdin gave us. Trailing newline from the heredoc gets
# stripped so length checks match what the user actually typed.
TEXT="$(cat)"
TEXT="${TEXT%$'\n'}"

# Length floor. Trim leading/trailing whitespace before counting so a
# justification of "    short    " is rejected on its real content.
TRIMMED="$(printf '%s' "$TEXT" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
if [ "${#TRIMMED}" -lt "$MIN_CHARS" ]; then
    echo "[/justify] RECHAZADA: justificación demasiado breve (${#TRIMMED} chars, mínimo ${MIN_CHARS})." >&2
    echo "Reescribe con contexto suficiente: qué cambias, por qué, y cuál es la consecuencia." >&2
    exit 1
fi

# Prompt-injection guard. The downstream LLM judge emits VERDICT: and
# REASONING: lines as its own protocol. A justification that begins a
# line with either token can dictate the judge's verdict by smuggling a
# fake answer into the prompt. Reject defensively at the earliest gate.
if printf '%s\n' "$TEXT" | grep -qiE '^[[:space:]]*(VERDICT|REASONING)[[:space:]]*:'; then
    echo "[/justify] RECHAZADA: justificación contiene línea reservada (VERDICT:/REASONING:)." >&2
    echo "Esos prefijos son del formato del juez LLM; reformula sin esos tokens al inicio de línea." >&2
    exit 1
fi

# jq is required to emit a structurally valid JSON state file. Fail
# loudly rather than silently writing malformed JSON the hook will then
# reject at consumption time.
if ! command -v jq >/dev/null 2>&1; then
    echo "[/justify] ENTORNO: jq no disponible en PATH; no puedo persistir state." >&2
    exit 2
fi

if ! mkdir -p "$STATE_DIR" 2>/dev/null; then
    echo "[/justify] ENTORNO: no puedo crear $STATE_DIR." >&2
    exit 2
fi

NOW="$(date +%s)"

# jq builds the JSON payload so the justification can contain quotes,
# backslashes, newlines, NULs and other JSON-hostile bytes without
# corrupting the file.
if ! jq -n \
        --arg text "$TEXT" \
        --argjson ts "$NOW" \
        --argjson ttl "$TTL_SECONDS" \
        '{justification: $text, created_at: $ts, ttl_seconds: $ttl, consumed: false}' \
        > "$STATE_FILE"; then
    echo "[/justify] ENTORNO: jq falló al escribir $STATE_FILE." >&2
    exit 2
fi

echo "[/justify] Justificación registrada (TTL ${TTL_SECONDS}s)."
echo "El próximo Edit/Write/MultiEdit grande o crítico la consumirá."
exit 0
