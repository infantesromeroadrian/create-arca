#!/bin/bash
# ARCA — TaskCreated event hook (Claude Code 2.1.84+)
#
# Fires when the agent creates a Task via the TaskCreate tool. We log
# every spawn — agent type, prompt prefix, isolation mode — so the
# Guardian Audit can correlate which delegations cost the most context
# and whether preflight (token-optimizer + skill-router) ran.
#
# Stays silent and exit-0; never blocks task creation. The blocking
# preflight enforcement lives in delegation-preflight-enforcer.sh
# (PreToolUse:Agent), not here.

set -uo pipefail
umask 077

LOG="${HOME}/.claude/state/task-created-audit.log"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || true

# P0-H1 fix (audit 2026-05-16): operator-supplied description and prompt
# may contain pasted credentials. Truncation to 80/120 chars is NOT
# sufficient — a leaked token at the START of the field still gets
# logged. Mask via the shared lib used by command_logger.sh.
# shellcheck source=lib/secrets-mask.sh
if [[ -f "${HOME}/.claude/hooks/lib/secrets-mask.sh" ]]; then
    source "${HOME}/.claude/hooks/lib/secrets-mask.sh"
fi

input="$(cat 2>/dev/null || true)"
ts="$(date -Iseconds)"

agent_type="$(printf '%s' "$input" | jq -r '.subagent_type // .agent_type // .tool_input.subagent_type // ""' 2>/dev/null)"
desc="$(printf '%s' "$input" | jq -r '.tool_input.description // .description // ""' 2>/dev/null | head -c 80)"
isolation="$(printf '%s' "$input" | jq -r '.tool_input.isolation // ""' 2>/dev/null)"
prompt_prefix="$(printf '%s' "$input" | jq -r '.tool_input.prompt // ""' 2>/dev/null | head -c 120 | tr '\n' ' ')"

if command -v mask_secrets >/dev/null 2>&1; then
    desc="$(mask_secrets "$desc")"
    prompt_prefix="$(mask_secrets "$prompt_prefix")"
fi

printf '%s | agent=%s | iso=%s | desc=%s | prompt=%s\n' \
    "$ts" "${agent_type:-?}" "${isolation:-default}" "${desc:-?}" "${prompt_prefix:-?}" \
    >> "$LOG"
exit 0
