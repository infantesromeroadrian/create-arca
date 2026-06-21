---
description: Read-only security audit of ARCA's OWN Claude Code harness (settings.json, hooks, agents, skills, MCP grants) per ADR-105. Surfaces secrets, over-broad permissions, hook-injection gaps, wildcard MCP grants, and over-privileged read-only agents. Exit 2 (CI gate) on any CRITICAL/HIGH. Never modifies a file.
allowed-tools: Bash(python3 ~/.claude/scripts/harness_audit.py:*)
argument-hint: "[--json] [--category CAT-1|CAT-2|CAT-3|CAT-4|CAT-5] [--repo PATH]"
---

# /harness-audit

Audit ARCA's own harness configuration for security drift. This is the
self-inspection counterpart to `/claude-config-audit` (which checks the config
against upstream Anthropic docs); `/harness-audit` checks the config against a
fixed set of security invariants and is fully build-native (stdlib + optional
PyYAML, no network, read-only).

Per ADR-105 Fase 1.

## Usage

```
/harness-audit                       # full table, all 5 categories
/harness-audit --json                # machine-readable (CI / dashboards)
/harness-audit --category CAT-2      # only the Permissions checks
/harness-audit --repo /path/to/repo  # audit a different ARCA checkout
```

## What it checks

| Category | What | Severity |
|---|---|---|
| CAT-1 Secrets | Disk scan of CLAUDE.md, agents/*.md, skills/*/SKILL.md, ~/.claude.json for hardcoded credentials (mirrors `hooks/detect-secrets.sh`). Skips the CVP org UUID and documentation placeholders. | HIGH (tracked artifact) / INFO (live auth store) |
| CAT-2 Permissions | `settings.json` allow/deny: `Bash(*)` blanket grant, `Read/Write/Edit(*)`, missing credential Read-deny paths, `skipDangerousModePermissionPrompt`. | HIGH / MEDIUM / INFO |
| CAT-3 Hook integrity | `prompt-critical-paths-guard.sh` coverage gap (hooks/*.sh not protected) + group/world-writable hook scripts. | MEDIUM / HIGH |
| CAT-4 MCP grants | Count of `mcp__<server>__*` wildcard grants + no per-subagent RBAC. | MEDIUM |
| CAT-5 Agent defs | Read-only / routing / classifier / auditor agents that hold write-capable tools (Bash/Write/Edit); `tools: '*'`; blocking-gate agents on cheaper models. | MEDIUM / LOW |

## Implementation

```bash
python3 ~/.claude/scripts/harness_audit.py $ARGUMENTS
```

The script defaults `--repo` to `$CLAUDE_PROJECT_DIR` (falling back to the known
local ARCA checkout), and always reads `~/.claude/settings.json`, `~/.claude.json`,
and `~/.claude/hooks/` for the runtime side of the audit.

## Exit codes

- `0` — no CRITICAL/HIGH findings (clean enough to pass a CI gate).
- `2` — at least one CRITICAL/HIGH finding; the gate fails.

## When to run

- Before any commit that touches `settings.json`, `hooks/**`, `agents/**`, or `skills/**`.
- As part of a periodic harness security review (pairs well with `/guardian-audit`).
- After adding a new MCP server or a new agent, to confirm grants stay scoped.

## Notes

- Read-only by design — it never edits, never writes, never rotates anything. The
  remediation column tells you what to fix; you apply it.
- The 3 INFO hits on `~/.claude.json` are the harness's own live OAuth/session
  tokens (expected runtime state, not a leak); the actionable check for that file
  is that it stays mode 600. Tokens in *tracked* artifacts are reported HIGH.
