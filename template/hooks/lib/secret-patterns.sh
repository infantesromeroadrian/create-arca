#!/bin/bash
# lib/secret-patterns.sh — single source of truth for credential/token regexes.
#
# WHY: detect-secrets.sh (pre-write blocker), post-tool-secrets-mask.sh (post-tool
# masker), and lib/secrets-mask.sh (input-masker for telemetry) all need the same
# regex catalog. Drift = silent bypass (ADR-108 §Rationale). This file is sourced
# by all three so adding a pattern here propagates everywhere atomically.
#
# Contract:
#   - Defines two arrays: SECRET_PATTERNS_ABSOLUTE (block always, even in
#     educational paths) and SECRET_PATTERNS_STANDARD (skip if path is educational).
#   - Each entry is "label|regex" — caller splits on first "|".
#   - Caller decides whether to block (exit 2), mask (sed), or flag (log).
#   - No side effects; safe to source multiple times.

# Absolute patterns — block/mask regardless of context (AWS keys, PEM private keys
# and similar are never legitimate in agent-authored content).
SECRET_PATTERNS_ABSOLUTE=(
    "aws-access-key|AKIA[0-9A-Z]{16}"
    "rsa-private-key|-----BEGIN RSA PRIVATE KEY-----"
    "ec-private-key|-----BEGIN EC PRIVATE KEY-----"
    "openssh-private-key|-----BEGIN OPENSSH PRIVATE KEY-----"
    "pgp-private-key|-----BEGIN PGP PRIVATE KEY BLOCK-----"
    "dsa-private-key|-----BEGIN DSA PRIVATE KEY-----"
)

# Standard patterns — service-specific tokens with low false-positive rate.
SECRET_PATTERNS_STANDARD=(
    "anthropic-key|sk-ant-(api|oat)[0-9]{2,}-[A-Za-z0-9_-]{20,}"
    "openai-key|sk-[a-zA-Z0-9]{20,}"
    "nvidia-key|nvapi-[a-zA-Z0-9_-]{20,}"
    "huggingface-token|hf_[A-Za-z0-9]{30,}"
    "github-pat|gh[pousr]_[A-Za-z0-9]{36,}"
    "github-fine-pat|github_pat_[A-Za-z0-9_]{82}"
    "slack-token|xox[bpoa]-[A-Za-z0-9-]{30,}"
    "google-api-key|AIza[0-9A-Za-z_-]{35}"
    "google-oauth|ya29\\.[0-9A-Za-z_-]{20,}"
    "langsmith-key|lsv2_(pt|sk)_[a-f0-9]{32}_[a-f0-9]{10}"
    "jwt|eyJ[A-Za-z0-9_-]{10,}\\.eyJ[A-Za-z0-9_-]{10,}\\.[A-Za-z0-9_-]{10,}"
    "bearer|Bearer\\s+[A-Za-z0-9._-]{20,}"
    # Atlassian (Jira/Confluence API tokens — long base64-ish)
    "atlassian-token|ATATT3[A-Za-z0-9_-]{60,}"
    # GitLab PAT (prefix glpat-)
    "gitlab-pat|glpat-[A-Za-z0-9_-]{20,}"
    # Linear API key (prefix lin_api_)
    "linear-key|lin_api_[A-Za-z0-9]{40,}"
    # Wolfram Alpha App ID (8-char uppercase alphanumeric — too short to be safe
    # alone, so only flag when adjacent to the typical API URL).
    "wolfram-appid|wolframalpha\\.com/[a-z]+\\?appid=[A-Z0-9]{8,}"
    # Kaggle token prefix KGAT_
    "kaggle-token|KGAT_[a-f0-9]{32,}"
    # Firecrawl API key prefix fc-
    "firecrawl-key|fc-[a-f0-9]{32,}"
    # Context7 API key prefix ctx7sk-
    "context7-key|ctx7sk-[a-f0-9-]{20,}"
    # Brave Search API key prefix BSAIh_ (observed format)
    "brave-key|BSAI[A-Za-z0-9_-]{30,}"
)

# Returns 0 if $1 (a path) is under an educational allowlist (CTF, red-teaming labs).
# Mirrors detect-secrets.sh's existing allowlist.
secret_patterns_is_educational_path() {
    local p="$1"
    [[ -z "$p" ]] && return 1
    if echo "$p" | grep -qiE '(/|^)(HTB|Academy|AI-Red-Teaming|red-teaming|red_teaming|CTF|htb-academy|ctf-notebooks|ctf_notebooks|bug-bounty|pentesting-labs)(/|$)'; then
        return 0
    fi
    return 1
}
