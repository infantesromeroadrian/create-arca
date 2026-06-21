#!/usr/bin/env bash
# claude-config-audit — runs the weekly audit by invoking @claude-code-guide
# with a structured prompt and persisting the result.
#
# Why this script exists separately from invoking the agent inline: the
# scheduled cron path needs a stable entry point that does not depend on
# the user's shell session or interactive Claude Code. The skill SKILL.md
# tells the agent (or human) what the audit covers; this script is the
# operational hook that the scheduler runs.
#
# Contract:
#   stdout — short status line (audit started / cached / failed)
#   stderr — diagnostic on failure
#   exit 0 — audit launched (whether sync or async)
#   exit 1 — environment failure (no claude CLI, no project dir)
#
# State:
#   $HOME/.claude/state/claude-config-audit/<YYYY-MM-DD>.md  (report)
#   $HOME/.claude/state/claude-config-audit/last-run.json    (metadata)
#   $HOME/.claude/state/claude-config-audit-blocker.flag     (only on BLOCKER)
#   $HOME/.claude/logs/claude-config-audit.jsonl             (audit trail)

set -uo pipefail

REPORT_DIR="${HOME}/.claude/state/claude-config-audit"
LOG_DIR="${HOME}/.claude/logs"
LOG_FILE="${LOG_DIR}/claude-config-audit.jsonl"
TODAY="$(date -u '+%Y-%m-%d')"
NOW_ISO="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

mkdir -p "$REPORT_DIR" "$LOG_DIR" || {
    echo "[claude-config-audit] cannot create state dirs" >&2
    exit 1
}

# Idempotency: same-day re-run reuses the report unless --force.
report_path="${REPORT_DIR}/${TODAY}.md"
if [[ -s "$report_path" && "${1:-}" != "--force" ]]; then
    echo "[claude-config-audit] report already exists for ${TODAY}: $report_path"
    echo "[claude-config-audit] use --force to regenerate"
    {
        printf '{"ts":"%s","action":"skip","reason":"same_day_cache","path":"%s"}\n' \
            "$NOW_ISO" "$report_path"
    } >> "$LOG_FILE" 2>/dev/null || true
    exit 0
fi

# The actual audit logic runs inside Claude Code via @claude-code-guide.
# This script writes the prompt to a tmp file and invokes `claude` headlessly
# so the cron path does not require an interactive session.
#
# If `claude` CLI is unavailable (e.g. running outside the workstation),
# emit a stub report and a warn log. This keeps the audit chain unbroken
# even when the binary has not been installed yet on the cron host.
if ! command -v claude >/dev/null 2>&1; then
    cat > "$report_path" <<EOF
# Claude Code config audit — ${TODAY}

**Status:** SKIPPED — \`claude\` CLI not available on this host.

The cron schedule fired but the audit could not run. Verify the scheduler
runs in an environment where \`claude\` is installed and authenticated.
EOF
    {
        printf '{"ts":"%s","action":"skip","reason":"no_claude_cli","path":"%s"}\n' \
            "$NOW_ISO" "$report_path"
    } >> "$LOG_FILE" 2>/dev/null || true
    echo "[claude-config-audit] claude CLI missing — wrote stub report"
    exit 0
fi

# Headless invocation. In --print mode there is no orchestrator to delegate
# to a subagent like @claude-code-guide, so the prompt must be self-contained
# and carry the full 20-point checklist inline. The previous version told
# the model to "delegate to @claude-code-guide" which is a no-op in headless,
# and ran on the default model (Haiku) which produced truncated output
# (~170 words instead of the documented 1500). Both fixed below:
#   - --model sonnet: capable enough for 1500-word structured output.
#   - --allowed-tools: WebFetch + WebSearch + Read + Bash so the model can
#     consult docs.anthropic.com in VIVO and read project state.
#   - inline 20-item checklist: the model reads the audit definition from
#     stdin instead of relying on a delegate-to-subagent pattern.
prompt_file=$(mktemp -t claude-config-audit-prompt.XXXXXX)
cat > "$prompt_file" <<'PROMPT_EOF'
You are running the claude-config-audit weekly check. Audit ARCA's Claude
Code configuration against the LIVE Anthropic documentation at
docs.anthropic.com/claude-code (use WebFetch / WebSearch — do NOT rely on
training data). Produce a structured 1500-word report.

Before scoring, read this memory file so previously documented MINOR drift
items get downgraded instead of re-counted as new findings:

  ~/.claude/projects/-home-⟦ host_alias ⟧-Desktop-⟦ host_alias ⟧-.claude/memory/project_audit_2026_05_02_minor_items.md

For each of the 20 items below, return: [ITEM N] severity (BLOCKER /
SERIOUS / MINOR / OK), one-line evidence (with doc URL), how ARCA uses it,
and a fix recommendation if not OK.

# A. Hooks payload + env vars
1. Hook stdin JSON schema per event (PreToolUse / PostToolUse / Stop /
   UserPromptSubmit / SessionStart / PreCompact / TaskCreated / TeammateIdle).
2. Environment variables exported to hooks (closed list per docs).
3. CLAUDE_SESSION_ID — exported as env var to hook subshells, or only
   present in the JSON payload?
4. Variable interpolation in the `command` field ($HOME, $CLAUDE_PROJECT_DIR,
   $USER).
5. Resolution of $CLAUDE_PROJECT_DIR when the hook lives in global
   ~/.claude/settings.json.

# B. Skills + slash commands env
6. Env vars inherited by a skill `run.sh` script invoked from a slash
   command.
7. Recommended channel for a skill to access the active session_id at
   runtime.
8. cwd of a skill execution vs $CLAUDE_PROJECT_DIR.

# C. Subagents / Agent Teams
9. session_id scoping for subagents (Task tool) and teammates
   (CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1).
10. Hook visibility inside a subagent — does the lead's session_id or the
    subagent's appear in the payload?
11. Hook payload field that distinguishes lead vs subagent vs teammate.

# D. State sharing between hooks/skills
12. Officially recommended pattern for hook ↔ skill state sharing.
13. Runtime-managed state storage (~/.claude/state/, ~/.claude/sessions/,
    etc.) — lifecycle and guarantees.

# E. Worktrees + multi-process
14. session_id behaviour across multiple parallel `claude` instances.
15. Coordination vs isolation between instances.
16. $CLAUDE_PROJECT_DIR scope per instance vs global.

# F. Patterns ARCA could be using incorrectly
17. `Bash(*)` blanket allow — anti-pattern in docs?
18. Hook matcher syntax — regex vs glob vs substring (formal schema).
19. PreToolUse `if:` field — exactly one rule per entry, or chainable?
20. Hook `type: "prompt"` with `model:` field — documented API or accidental?

End with a final tally line:

  TALLY: BLOCKER=N SERIOUS=N MINOR=N OK=N

If BLOCKER > 0, also state which items and what fix is required to clear
the blocker flag.

Hard cap: 1500 words. Be concise but complete — every item gets its line.
PROMPT_EOF

# Run the audit. Capture full stderr to the log on failure but do not
# block the cron — fail-safe is "no audit ran today, try again next week".
# Tools allowed: WebFetch + WebSearch + Read for live doc lookup, Bash for
# light state introspection. No Write tool — output is captured via
# --print stdout redirect to the report path. No Edit / MultiEdit so the
# audit can never silently mutate ARCA config while reading it.
if ! claude --print \
        --model sonnet \
        --allowed-tools "WebFetch WebSearch Read Bash" \
        --no-session-persistence \
        < "$prompt_file" > "${report_path}.tmp" 2>>"${LOG_FILE}.stderr"; then
    rm -f "$prompt_file" "${report_path}.tmp"
    {
        printf '{"ts":"%s","action":"fail","reason":"claude_cli_error"}\n' "$NOW_ISO"
    } >> "$LOG_FILE" 2>/dev/null || true
    echo "[claude-config-audit] claude CLI returned non-zero" >&2
    exit 1
fi

mv "${report_path}.tmp" "$report_path"
rm -f "$prompt_file"

# Truncation sanity check. The prompt mandates a 1500-word ceiling but the
# 2026-05-02 incident produced 172-word reports because the previous
# version ran on the default model (Haiku) without an inline prompt.
# Anything below 800 words almost certainly means the model returned a
# summary instead of a full audit. Flag it so the operator knows to rerun
# manually rather than trusting a silently-truncated report.
report_words=$(wc -w < "$report_path" | tr -d ' ')
if [[ "$report_words" -lt 800 ]]; then
    {
        printf '{"ts":"%s","action":"warn","reason":"report_truncated","words":%s,"path":"%s"}\n' \
            "$NOW_ISO" "$report_words" "$report_path"
    } >> "$LOG_FILE" 2>/dev/null || true
    echo "[claude-config-audit] WARN: report has only ${report_words} words (< 800)" >&2
    echo "[claude-config-audit] check ${LOG_FILE}.stderr for model errors and consider --force rerun" >&2
fi

{
    printf '{"ts":"%s","action":"complete","path":"%s","words":%s}\n' \
        "$NOW_ISO" "$report_path" "$report_words"
} >> "$LOG_FILE" 2>/dev/null || true

echo "[claude-config-audit] report written to $report_path (${report_words} words)"
exit 0
