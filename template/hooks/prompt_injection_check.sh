#!/bin/bash
set -euo pipefail

# PreToolUse hook — detects prompt injection patterns in user-facing content

INPUT=$(cat)
CONTENT=$(echo "$INPUT" | jq -r '.tool_input.content // .tool_input.command // .tool_input.new_string // empty' 2>/dev/null || echo "")

[[ -z "$CONTENT" ]] && exit 0

# Prompt injection patterns — five independent detectors joined by `|` in grep -qiE.
#
# "jailbreak" was originally matched as a bare keyword which produced false
# positives on defensive / technical mentions ("jailbreak detection",
# "anti-jailbreak benchmark", "jailbreak catalog"). The keyword now requires an
# adversarial context: either an imperative verb before it, or an adversarial
# object after it. Task #47.
# `\w+\s+){0,3}` allows up to 3 modifier words between the verb and the target
# keyword. Closes pre-existing bypasses surfaced during Task #47 audit:
#   - "ignore all the above instructions" (was passing on the old adjacent-only regex)
#   - "forget all your rules" (same)
# The bound `{0,3}` keeps the regex non-explosive (no catastrophic backtracking
# with grep -E NFA) while covering the common adversarial phrasings.
#
# Design tradeoff — jailbreak object whitelist is intentionally CLOSED
# (Task #51 ADV-1). The pattern below catches `jailbreak the {model,system,
# llm,chatbot,ai,assistant,safety,guardrails,prompt}` but NOT novel
# adversarial objects like "jailbreak the alignment", "jailbreak the
# firmware", "jailbreak the RLHF layer". Those are out-of-scope by design
# for this Layer 1 keyword filter; deeper detection is Layer 2 responsibility
# (runtime guardrails, classifier-based moderation). Expanding the whitelist
# is feasible but trades false-positive risk on legitimate writeups
# (e.g. "jailbreak the alignment training pipeline" in an interp paper).
# See tests/test_prompt_injection_check.sh test_17/18 for the contract.
PATTERNS=(
  'ignore\s+(\w+\s+){0,3}(previous|prior|above)\s+instructions'
  'forget\s+(\w+\s+){0,3}(rules|instructions|system)'
  'act\s+as\s+DAN'
  '(perform|execute|do|attempt|run|try|let'\''?s|please)\s+a?\s*jailbreak'
  'jailbreak\s+(the|this|your|my|its)\s+(model|system|llm|chatbot|ai|assistant|safety|guardrails|prompt)'
  'you\s+are\s+now\s+unrestricted'
)
REGEX="$(IFS='|'; echo "${PATTERNS[*]}")"

if echo "$CONTENT" | grep -qiE "$REGEX"; then
  echo "BLOCKED: prompt injection pattern detected" >&2; exit 2
fi

exit 0
