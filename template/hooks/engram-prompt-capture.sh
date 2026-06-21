#!/usr/bin/env bash

export PATH="$HOME/go/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"  # ARCA: ensure engram + brew binaries discoverable
# ARCA — UserPromptSubmit Engram capture hook
#
# Captures user prompts to Engram for later semantic search. ⟦ user_name ⟧'s
# Engram stats showed Prompts=0 because mem_save_prompt was never invoked.
# This hook closes that gap by writing every meaningful prompt to the
# local Engram DB via the engram CLI.
#
# Filtering policy (skip on any match):
#   - prompt starts with "/" (slash command — already structured)
#   - prompt length < 100 chars (conversational — low retrieval value)
#   - prompt contains a system-reminder block (system-injected, not human)
#   - prompt looks like it contains a secret (tvly-, sk-, gho_, AKIA, etc.)
#
# Operation:
#   - Reads JSON from stdin: { prompt, cwd, session_id, ... }
#   - Spawns the engram save in background — does NOT block the turn.
#   - Always exits 0; this is a passive capture, never a gate.
#   - Writes nothing to stdout; this hook does not inject context (a
#     sibling hook user-prompt-context-injector.sh handles injection).

set -uo pipefail

payload="$(cat -)"

# Extract fields. jq is mandatory; fall through if missing.
if ! command -v jq >/dev/null 2>&1; then
    exit 0
fi

prompt=$(printf '%s' "${payload}" | jq -r '.prompt // empty' 2>/dev/null || echo "")
cwd=$(printf '%s' "${payload}" | jq -r '.cwd // empty' 2>/dev/null || echo "${PWD}")
session_id=$(printf '%s' "${payload}" | jq -r '.session_id // empty' 2>/dev/null || echo "")

# Filter 1: empty
[[ -z "${prompt}" ]] && exit 0

# Filter 2: slash commands
if [[ "${prompt}" =~ ^/[a-z] ]]; then
    exit 0
fi

# Filter 3: too short (conversational chatter)
# Lowered from 100 → 30 chars per ⟦ user_name ⟧ — captures meaningful instructions
# like "borra el repo X de github" but still drops "ok", "sí", "todas".
if (( ${#prompt} < 30 )); then
    exit 0
fi

# Filter 4: system-reminder content (not human-authored)
if [[ "${prompt}" == *"<system-reminder>"* ]]; then
    exit 0
fi

# Filter 5: secret-shaped content. Defense in depth — engram is local
# but a leak into the DB on a synced or shared machine would still be
# bad. Anchored prefixes only — no naked hex matchers (those produced
# false positives on SHA-256 digests, git long hashes, HF model hashes).
if [[ "${prompt}" =~ sk-ant-[A-Za-z0-9_-]{30,} ]] \
    || [[ "${prompt}" =~ sk-proj-[A-Za-z0-9_-]{30,} ]] \
    || [[ "${prompt}" =~ sk-[A-Za-z0-9]{40,} ]] \
    || [[ "${prompt}" =~ tvly-[A-Za-z0-9]{20,} ]] \
    || [[ "${prompt}" =~ wandb_v1_[A-Za-z0-9_]{40,} ]] \
    || [[ "${prompt}" =~ gho_[A-Za-z0-9]{30,} ]] \
    || [[ "${prompt}" =~ ghp_[A-Za-z0-9]{30,} ]] \
    || [[ "${prompt}" =~ glpat-[A-Za-z0-9_-]{20,} ]] \
    || [[ "${prompt}" =~ AKIA[0-9A-Z]{16} ]] \
    || [[ "${prompt}" =~ AIza[0-9A-Za-z_-]{35} ]] \
    || [[ "${prompt}" =~ xox[baprs]-[0-9A-Za-z-]{20,} ]] \
    || [[ "${prompt}" =~ eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,} ]]; then
    exit 0
fi

# Resolve project name. Prefer git remote slug, fall back to cwd basename.
cd "${cwd}" 2>/dev/null || true
project=""
if remote_url=$(git config --get remote.origin.url 2>/dev/null); then
    # Strip .git suffix and trailing slash; basename of the result.
    project=$(basename "${remote_url%.git}")
fi
if [[ -z "${project}" ]]; then
    project=$(basename "${cwd}")
fi

# Build a compact title. Engram CLI requires title + content.
ts=$(date +%s)
short_id="${session_id:0:8}"
title="prompt ${ts} ${short_id}"

# Spawn save in background. nohup detaches; output discarded.
# Avoids blocking the user's turn even if engram is slow.
(
    # Note: engram CLI's `save` writes to the observations table,
    # tagged with --type. The "Prompts:" counter shown by `engram
    # stats` is a separate field updated only by the MCP tool
    # mem_save_prompt; bash hooks cannot increment it directly.
    # Tagging --type=prompt makes the observation discoverable by
    # `engram search --type prompt` even though the counter stays 0.
    nohup engram save "${title}" "${prompt}" \
        --type=prompt \
        --project="${project}" \
        >/dev/null 2>&1 &
) &

exit 0
