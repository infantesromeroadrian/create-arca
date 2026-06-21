#!/bin/bash
# hooks/lib/secrets-mask.sh — shared secret masking helper.
#
# Single source of truth for credential pattern masking. Consumed by
# pre-write loggers (command_logger.sh, agent-invocation-logger.sh)
# to prevent secrets from landing in telemetry.jsonl, and conceptually
# paired with hooks/post-tool-secrets-mask.sh which masks tool *output*
# in the response stream — this helper masks tool *input* before logs.
#
# USAGE:
#   source "${HOME}/.claude/hooks/lib/secrets-mask.sh"
#   masked=$(mask_secrets "$raw_text")
#
# CONTRACT:
#   - Pure stdout function: prints masked text, never modifies state.
#   - Patterns are conservative (high precision, accepts some false
#     negatives over false positives — the gate at write-time is
#     detect-secrets.sh which is stricter).
#   - If input is empty, prints empty (no-op).
#   - Replacement format: [MASKED:<label>]
#
# PATTERNS — kept in sync with hooks/post-tool-secrets-mask.sh:
#   - AWS access key:      AKIA[0-9A-Z]{16}
#   - GitHub PAT classic:  ghp_[A-Za-z0-9]{36}
#   - GitHub fine PAT:     github_pat_[A-Za-z0-9_]{82}
#   - Anthropic key:       sk-ant-[A-Za-z0-9_-]{20,}
#   - OpenAI key:          sk-[A-Za-z0-9]{32,}
#   - Generic Bearer:      Bearer [A-Za-z0-9._-]{20,}
#   - JWT:                 eyJ[...].eyJ[...].[...]
#
# UPDATE POLICY: if a new credential class needs masking, add it here
# AND to post-tool-secrets-mask.sh in the same commit to keep input/
# output coverage symmetric. Document the addition in the file header.

mask_secrets() {
    local text="$1"
    [[ -z "$text" ]] && { printf ''; return 0; }

    printf '%s' "$text" \
        | sed -E 's/AKIA[0-9A-Z]{16}/[MASKED:aws-key]/g' \
        | sed -E 's/ghp_[A-Za-z0-9]{36}/[MASKED:github-pat]/g' \
        | sed -E 's/github_pat_[A-Za-z0-9_]{82}/[MASKED:github-fine-pat]/g' \
        | sed -E 's/sk-ant-[A-Za-z0-9_-]{20,}/[MASKED:anthropic-key]/g' \
        | sed -E 's/sk-[A-Za-z0-9]{32,}/[MASKED:openai-key]/g' \
        | sed -E 's/Bearer [A-Za-z0-9._-]{20,}/[MASKED:bearer-token]/g' \
        | sed -E 's/eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}/[MASKED:jwt]/g'
}
