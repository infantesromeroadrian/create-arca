#!/bin/bash
# ARCA — Context window estimator (sourced, not executed).
#
# Helpers to estimate how full Claude Code's context window is, based on
# the session transcript that the runtime writes under
# ~/.claude/projects/<project-slug>/<session-uuid>.jsonl
#
# Implements ADR-039 (Context window monitoring at 40% threshold). The
# threshold default comes from the Vercel D0 / harness-engineering
# literature surfaced via the 2026-04-29 BettaTech video and the GitHub
# issue on Claude Code recommending `/compact` at ~40% to avoid the
# degradation that begins around 20% of any large-context model.
#
# Heuristic: chars / 4 ≈ tokens. Slightly biased toward overestimation
# for transcripts dense in JSON (tool inputs/outputs) — that bias is
# acceptable here because we want to err on the side of warning earlier,
# not later.
#
# Override via env vars:
#   ARCA_CONTEXT_WINDOW_TOKENS  — total window in tokens (default: 1000000 for Opus 4.8 1M)
#   ARCA_CONTEXT_THRESHOLD      — warn threshold pct (default: 40)
#
# Functions:
#   context_estimate_tokens <transcript_path>           — echoes integer (token count, 0 if missing)
#   context_estimate_pct <transcript_path> [<window>]   — echoes integer (% of window)
#   context_window_size                                 — echoes the configured window size
#   context_threshold_pct                               — echoes the configured threshold

set -uo pipefail

context_window_size() {
    echo "${ARCA_CONTEXT_WINDOW_TOKENS:-1000000}"
}

context_threshold_pct() {
    echo "${ARCA_CONTEXT_THRESHOLD:-40}"
}

context_estimate_tokens() {
    local transcript="$1"
    [[ -z "$transcript" ]] && { echo 0; return 0; }
    [[ -f "$transcript" ]] || { echo 0; return 0; }
    local bytes
    bytes="$(wc -c < "$transcript" 2>/dev/null | tr -d ' ')"
    [[ -z "$bytes" ]] && { echo 0; return 0; }
    # chars / 4 ≈ tokens. Integer math, biased toward overestimation.
    echo $(( bytes / 4 ))
}

context_estimate_pct() {
    local transcript="$1"
    local window="${2:-$(context_window_size)}"
    [[ "$window" -le 0 ]] && { echo 0; return 0; }
    local tokens
    tokens="$(context_estimate_tokens "$transcript")"
    echo $(( tokens * 100 / window ))
}
