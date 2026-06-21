#!/usr/bin/env bash
# ARCA — Prompt-critical paths guard (Task #53, Lopopolo Prio 2)
#
# Defends against the prompt-poisoning vector: an agent (subagent OR main) that
# modifies a file in the prompt-critical set (agents/*.md, skills/*/SKILL.md,
# CLAUDE.md, rules/*.md, commands/*.md) and embeds adversarial instructions
# in the new content. Without this gate, the modified prompt is silently
# loaded by every future invocation of that agent / skill / command — behavior
# drift becomes permanent and invisible until somebody notices the output is
# off (or worse, until an attacker exploits the drift).
#
# This is the COMPLEMENT to hooks/prompt_injection_check.sh (Task #47), which
# validates `tool_input.content/command/new_string` against adversarial
# phrasings on every Bash/Write/Edit. That hook protects against attackers
# steering Claude via user-facing inputs. THIS hook protects against
# attackers (or runaway agents) corrupting the prompt files themselves so
# the entire ecosystem ingests poisoned instructions on next load.
#
# Trigger: PreToolUse on Edit / Write / MultiEdit when the modified path
# matches the prompt-critical set.
#
# Scope (v1):
#   - Lexical pattern match on the NEW content being written. Same regex
#     style as prompt_injection_check.sh — context-bound to reduce false
#     positives on technical / defensive mentions.
#   - Diff-size warning: writes > 500 lines emit a stderr warning but do
#     NOT block. The intent is to surface unusually large prompt rewrites
#     for HITL attention, not to ban refactors.
#
# Out of scope (v2, ARCA-DEBT-005):
#   - Structural diff analysis (tools: frontmatter mutation, model
#     downgrade detection, critic_gate_required: true → false).
#   - LLM-as-judge semantic review of the diff (Ollama Qwen 2.5 7B,
#     same pattern as hooks/lib/diff-judge.sh).
#   - Cross-file consistency checks (e.g. agents/X.md references skill Y
#     that suddenly removed required_keywords).
#
# Bypass: ARCA_PROMPT_GUARD_BYPASS=1 — audit-logged to
# ~/.claude/state/prompt-guard-bypasses.log so legitimate bypass usage
# is observable in /morning-briefing and weekly Guardian Audit.

set -uo pipefail

LOG_DIR="${HOME}/.claude/state"
BYPASS_LOG="${LOG_DIR}/prompt-guard-bypasses.log"

# Bypass — audit-logged
if [[ "${ARCA_PROMPT_GUARD_BYPASS:-0}" == "1" ]]; then
    mkdir -p "$LOG_DIR" 2>/dev/null || true
    if [[ -w "$LOG_DIR" || ! -e "$LOG_DIR" ]]; then
        echo "$(date -Iseconds) | bypassed via ARCA_PROMPT_GUARD_BYPASS=1" >> "$BYPASS_LOG" 2>/dev/null
    fi
    exit 0
fi

payload="$(cat - 2>/dev/null || echo '{}')"

if ! command -v jq >/dev/null 2>&1; then
    # Fail-open: missing jq must not block the operator's session.
    exit 0
fi

# Extract path + new content. Edit/MultiEdit use new_string; Write uses content.
file_path=$(printf '%s' "$payload" | jq -r '.tool_input.file_path // .tool_input.filePath // empty' 2>/dev/null)
new_content=$(printf '%s' "$payload" | jq -r '.tool_input.content // .tool_input.new_string // empty' 2>/dev/null)

[[ -z "$file_path" ]] && exit 0
[[ -z "$new_content" ]] && exit 0

# In-scope path matching. Patterns mirror the actual ARCA prompt surface.
# Both absolute and bare-relative paths must match — the runtime sends file
# paths in both shapes depending on cwd context. Earlier draft only matched
# `*/<dir>/<file>` which evaded on bare `<dir>/<file>` (B1 from @code-critic
# Task #53 ciclo 1 audit).
in_scope=0
case "$file_path" in
    */agents/*.md|agents/*.md)                      in_scope=1 ;;
    */skills/*/SKILL.md|skills/*/SKILL.md)          in_scope=1 ;;
    */CLAUDE.md|CLAUDE.md)                          in_scope=1 ;;
    */rules/*.md|rules/*.md)                        in_scope=1 ;;
    */commands/*.md|commands/*.md)                  in_scope=1 ;;
esac

[[ "$in_scope" -eq 1 ]] || exit 0

# Catalog allowlist — files that document attack vectors defensively. These
# files NEED to contain literal phrasings ("jailbreak", "skip the critic")
# in references / arXiv citations / OWASP LLM Top 10 mapping so the agent
# or skill recognizes those vectors. Subjecting them to the lexical scan
# would force routine bypass on every legitimate update of the defensive
# catalog, normalizing the bypass mechanism and destroying the audit
# signal.
#
# Empirical note: a sweep of the current repo (2026-05-11) found ZERO
# in-scope files triggering the regex — the actual catalog files use
# technical references (paper titles, MITRE ATLAS IDs, JailbreakBench
# leaderboard names) that do not match the context-bound patterns. The
# allowlist is preventive: when the catalog grows or new defensive
# agents land, the allowlist absorbs them without operator-side bypass.
#
# Allowlisted files still receive the diff-size warning (large rewrites
# of catalog files deserve HITL attention).
is_catalog=0
case "$file_path" in
    */agents/ai-red-teamer.md|agents/ai-red-teamer.md)                                  is_catalog=1 ;;
    */agents/trust-and-safety-engineer.md|agents/trust-and-safety-engineer.md)          is_catalog=1 ;;
    */agents/alignment-researcher.md|agents/alignment-researcher.md)                    is_catalog=1 ;;
    */agents/evals-engineer.md|agents/evals-engineer.md)                                is_catalog=1 ;;
    */skills/owasp-security/SKILL.md|skills/owasp-security/SKILL.md)                    is_catalog=1 ;;
    */skills/ml-security/SKILL.md|skills/ml-security/SKILL.md)                          is_catalog=1 ;;
    */skills/cybersecurity/SKILL.md|skills/cybersecurity/SKILL.md)                      is_catalog=1 ;;
    */skills/bb-methodology/SKILL.md|skills/bb-methodology/SKILL.md)                    is_catalog=1 ;;
    */skills/full-bug-hunt/SKILL.md|skills/full-bug-hunt/SKILL.md)                      is_catalog=1 ;;
    */skills/web2-vuln-classes/SKILL.md|skills/web2-vuln-classes/SKILL.md)              is_catalog=1 ;;
esac

# Adversarial patterns specific to prompt poisoning. Extends the Task #47
# catalog with vectors unique to prompt files (gate-disable phrasings).
# All patterns are case-insensitive via grep -i.
PATTERNS=(
    # From Task #47 — generic prompt injection (re-applied here because a
    # poisoned prompt file would attempt the same tricks at load time).
    'ignore\s+(\w+\s+){0,3}(previous|prior|above)\s+instructions'
    'forget\s+(\w+\s+){0,3}(rules|instructions|system)'
    'act\s+as\s+DAN'
    '(perform|execute|do|attempt|run|try|let'\''?s|please)\s+a?\s*jailbreak'
    'jailbreak\s+(the|this|your|my|its)\s+(model|system|llm|chatbot|ai|assistant|safety|guardrails|prompt)'
    'you\s+are\s+now\s+unrestricted'

    # Gate-disable phrasings unique to prompt-poisoning. An attacker who
    # controls the prompt content can disable enforcement at load time
    # without ever touching the hook scripts themselves. These patterns
    # encode the gate-bypass intent in natural language.
    '(skip|bypass|disable|ignore|remove)\s+(all\s+|the\s+)?(critic|critic\s+gate|review|reviews|gates|hooks|enforcement|guardrails)'
    '(exempt|excluded)\s+from\s+(all\s+|the\s+)?(critic|review|reviews|gate|gates|enforcement)'
    'always\s+(approve|accept|pass)\s+(this|all|every)'
    'auto[- ]?approve\s+(this|all|every|without)'
    'do\s+not\s+(invoke|call|delegate\s+to)\s+@code-critic'
    'do\s+not\s+(invoke|call|delegate\s+to)\s+@math-critic'
    'do\s+not\s+require\s+(human|hitl|⟦ user_name ⟧)\s+(approval|sign[- ]?off)'
    'ignore\s+(all\s+)?prior\s+agent\s+instructions'
    'delete\s+(all\s+)?(gates|hooks|enforcement)'
)
REGEX="$(IFS='|'; echo "${PATTERNS[*]}")"

if [[ "$is_catalog" -eq 1 ]]; then
    # Allowlisted catalog file — skip lexical scan, fall through to the
    # diff-size warning below. This is the documented escape hatch that
    # makes the audit log meaningful: bypasses are reserved for genuinely
    # surprising cases, not for routine defensive-catalog updates.
    :
elif echo "$new_content" | grep -qiE "$REGEX"; then
    {
        echo "=========================================================================="
        echo "[prompt-guard] BLOCKED — prompt poisoning pattern detected"
        echo "=========================================================================="
        echo "File: $file_path"
        echo ""
        echo "The new content contains an adversarial pattern (gate-disable, jailbreak,"
        echo "or ignore-prior-instructions phrasing). Modifying a prompt-critical file"
        echo "with such content would silently alter the behavior of every future"
        echo "invocation of the affected agent / skill / command."
        echo ""
        echo "If this is a legitimate refactor that happens to contain the phrasing"
        echo "(e.g. documenting an attack in a comment, or a test fixture), bypass via:"
        echo "  ARCA_PROMPT_GUARD_BYPASS=1"
        echo "Bypasses are audit-logged at ~/.claude/state/prompt-guard-bypasses.log"
        echo ""
        echo "Otherwise, revise the content to remove the adversarial phrasing."
        echo "=========================================================================="
    } >&2
    exit 2
fi

# Diff-size warning (non-blocking). Surface unusually large prompt rewrites
# for HITL attention. Threshold tuned to catch full-file rewrites of typical
# agent / skill prompts (most are 100-400 lines).
line_count=$(printf '%s' "$new_content" | wc -l | tr -d ' ')
if [[ "${line_count:-0}" -gt 500 ]]; then
    {
        echo "[prompt-guard] WARN — large prompt rewrite ($line_count lines) on $file_path"
        echo "[prompt-guard]        consider reviewing the diff before accepting"
    } >&2
fi

exit 0
