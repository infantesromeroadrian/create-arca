# ARCA Hook Directory — ~/.claude/hooks/

Global PreToolUse/PostToolUse hooks for the ARCA agent ecosystem.
All hooks receive JSON on stdin (Claude Code hook protocol v2+) and
write audit logs to `~/.claude/logs/`.

## Hook inventory

| Script | Trigger | Purpose |
|---|---|---|
| `agent-invocation-logger.sh` | PostToolUse:Agent | Logs every agent invocation to telemetry |
| `agent-running-cleanup.sh` | PostToolUse:Agent | Removes live-agent marker files on completion |
| `agent-running-tracker.sh` | PreToolUse:Agent | Writes live-agent marker files for statusline |
| `block-dangerous.sh` | PreToolUse:Bash | Blocks rm -rf on critical paths, force-push to main, etc. |
| `code-critic-gate-enforcer.sh` | PostToolUse:Agent | Blocks @chief-architect or @deployment without prior @code-critic |
| `command_logger.sh` | PostToolUse:Bash | Appends every bash command to session log |
| `critic-feedback-tracker.sh` | PostToolUse:Agent | Tracks code-critic outcomes for drift detection |
| `debug-loop-detector.sh` | PostToolUse:Read/Edit/Write | Detects read-edit-read-edit loops indicating stuck agents |
| `delegation-preflight-enforcer.sh` | PreToolUse:Agent | Enforces @token-optimizer + @skill-router before specialist agents |
| `detect-secrets.sh` | PreToolUse:Write/Edit | Blocks hardcoded secrets (API keys, tokens, passwords) |
| `gemini-gate.sh` | PreToolUse:Write/Edit | Blocks write operations to sensitive ARCA config files |
| `git-commit-validator.sh` | PreToolUse:Bash | Enforces conventional commits format + ≤72 char subject |
| `hud-state-writer.sh` | PostToolUse:* | Updates ~/.claude/hud.json for Waybar statusline |
| `instructions-loaded-logger.sh` | SessionStart | Logs which instruction files were loaded at session start |
| `log-activity.sh` | PostToolUse:* | Appends all tool use events to activity log |
| `math-critic-advisor.sh` | PostToolUse:Edit/Write | Advisory: suggests @math-critic for ML code changes |
| `math-critic-gate-enforcer.sh` | PostToolUse:Agent | Blocks @code-critic on ML-producer code without prior @math-critic |
| `prompt_injection_check.sh` | PreToolUse:Bash | Detects prompt injection patterns in bash commands |
| `session-fatigue-detector.sh` | PostToolUse:* | Warns when session has been running >N hours |
| `session_start.sh` | SessionStart | Loads session context, writes session-start-epoch marker |
| `skill-extractor.sh` | PostToolUse:Bash | Extracts skill usage patterns for @skill-router optimization |
| `uncommitted-work-detector.sh` | PostToolUse:Edit/Write/Bash | Warns when edits accumulate without a commit |
| `user-prompt-context-injector.sh` | PreToolUse:* | Injects ARCA context into user prompts |
| `worktree-create-autogit.sh` | WorktreeCreate | Auto-initializes git repo if cwd lacks one (prevents isolation:worktree failures) |
| `worktree-isolation-enforcer.sh` | PreToolUse:Bash | **Blocks git commit/add from main repo** (T15) — see section below |

---

## worktree-isolation-enforcer.sh

**Ticket**: T15  
**Installed**: 2026-04-25  
**Trigger**: PreToolUse:Bash

### Problem

Three consecutive incidents (commits `b26d8b0`, `26e011a`, `aa2427d`) occurred
when agents with `isolation:worktree` executed `git commit` directly on the
main project repo instead of their assigned worktree path. No existing hook
blocked these operations. Post-facto audit was required for all three.

### What it detects

A `git commit` or `git add` operation executed from a directory that:
1. Is inside a known ARCA project root (Work, Personal, HTB, Kaggle paths), AND
2. Does NOT contain `/.claude/worktrees/` in its path.

If both conditions are true, the agent is committing from the main repo —
which violates worktree isolation.

### Modes

| Mode | How to activate | Behavior |
|---|---|---|
| DRY-RUN (default) | `ARCA_WORKTREE_ISOLATION_ENFORCE` unset | Logs violation to `~/.claude/logs/worktree-isolation-violations.jsonl`, emits stderr warning, exits 0 |
| ENFORCE | `export ARCA_WORKTREE_ISOLATION_ENFORCE=1` | Same logging + exits 2 (blocks the Bash call) |

The default is DRY-RUN to allow observation before hard enforcement.
To activate hard blocking globally:
```bash
echo 'export ARCA_WORKTREE_ISOLATION_ENFORCE=1' >> ~/.zshrc
```

### Bypass (single-use)

For legitimate main-repo commits (e.g., post-merge doc fix, CLAUDE.md update):

```bash
echo "post-merge CLAUDE.md update — main-repo commit intentional" > /tmp/arca-worktree-bypass
# then retry git commit
```

The bypass is atomically consumed on use and logged to the violation log.

### Disabling temporarily

```bash
unset ARCA_WORKTREE_ISOLATION_ENFORCE  # revert to dry-run
# or remove from settings.json PreToolUse:Bash hooks array
```

### Violation log

```bash
cat ~/.claude/logs/worktree-isolation-violations.jsonl | jq .
```

---

## Hook input format (Claude Code v2+)

Hooks receive JSON on stdin:

```json
{
  "tool_name": "Bash",
  "tool_input": {
    "command": "git commit -m \"...\"",
    "description": "optional description"
  },
  "cwd": "/path/to/current/working/directory",
  "session_id": "session-uuid"
}
```

For Agent tools: `tool_input.subagent_type` contains the agent name.

## Adding a new hook

1. Create `~/.claude/hooks/<name>.sh`, `chmod +x`.
2. Add entry to `~/.claude/settings.json` under `hooks.PreToolUse` or `hooks.PostToolUse`.
3. Use `exit 0` for allow, `exit 2` for block (message to stderr shown to Claude).
4. Always handle missing `jq` gracefully: `command -v jq >/dev/null || exit 0`.
5. Add a row to the inventory table above.
