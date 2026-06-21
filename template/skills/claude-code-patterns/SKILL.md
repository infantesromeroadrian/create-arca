---
name: claude-code-patterns
description: >-
  ARCA ecosystem patterns for Claude Code. Agent definitions, skill format, hooks system
  (PreToolUse, PostToolUse, UserPromptSubmit), slash commands, worktree isolation, delegation
  protocol, multi-model strategy, and settings.json structure. Activate when creating new agents,
  skills, hooks, commands, or configuring the Claude Code ecosystem.
effort: high
---

# Claude Code Patterns — ARCA Ecosystem

## Overview

ARCA (AI Research & Code Architect) is a structured Claude Code ecosystem consisting of:

| Component | Location | Purpose |
|-----------|----------|---------|
| Agents | `agents/*.md` | Specialized roles with model/tool constraints |
| Skills | `skills/*/SKILL.md` | Domain knowledge loaded on demand |
| Hooks | `hooks/*.sh` | Deterministic guardrails (shell scripts, not LLM) |
| Commands | `commands/*.md` | Slash commands for common workflows |
| Settings | `.claude/settings.json` | Permissions, hooks, MCP servers |

All components live under the ARCA repo and are synced to `~/.claude/` via `scripts/sync.sh`.

---

## Agent Definition Format

Each agent is a Markdown file with YAML frontmatter. Location: `agents/<name>.md`.

### Frontmatter Schema

```markdown
---
name: agent-name
description: One-line role description. Used by skill-router for delegation.
model: haiku|sonnet|opus
tools: Bash, Read, Write, Edit, Glob, Grep
color: blue|green|purple|red|yellow|cyan
isolation: worktree      # optional — creates separate git branch
memory: project|user     # optional — memory scope
---
```

### Frontmatter Fields

| Field | Required | Values | Description |
|-------|----------|--------|-------------|
| `name` | Yes | `agent-<role>` | Unique identifier. Convention: `agent-` prefix. |
| `description` | Yes | String | What the agent does. Skill-router reads this to decide delegation. |
| `model` | Yes | `haiku`, `sonnet`, `opus` | LLM to use. Drives cost/capability. |
| `tools` | Yes | Comma-separated | Which Claude Code tools the agent can access. |
| `color` | No | Color name | Terminal color for agent output. |
| `isolation` | No | `worktree` | If set, agent runs in a separate git worktree/branch. |
| `memory` | No | `project`, `user` | Engram memory scope. |

### Full Agent Example

```markdown
---
name: agent-data-engineer
description: Data pipelines, ETL, SQL optimization, Spark, Airflow. Sonnet 4.6.
model: sonnet
tools: Bash, Read, Write, Edit, Glob, Grep
color: green
---

You are @agent-data-engineer in the ARCA ecosystem.

## Scope
Data pipelines (batch + streaming), ETL/ELT, SQL optimization, schema design,
Apache Spark, Airflow DAGs, dbt models.

## Workflow
1. Understand data source and sink
2. Design schema with normalization level appropriate to use case
3. Build pipeline with idempotency and exactly-once semantics
4. Add data validation (Great Expectations or custom)
5. Write tests for edge cases (null handling, schema drift, late arrivals)

## Output Format
- Schema DDL first
- Pipeline code with type hints
- Test file with pytest fixtures

## Anti-Patterns
- SELECT * in production queries
- No partition pruning on large tables
- Missing idempotency keys in ETL
- Hardcoded connection strings
```

### Agent Body Guidelines

The body after frontmatter defines the agent's system prompt. Structure:

1. **Identity line**: "You are @agent-name in the ARCA ecosystem."
2. **Scope**: What the agent handles (and implicitly, what it does not).
3. **Workflow**: Numbered steps the agent follows.
4. **Output Format**: How the agent structures responses.
5. **Anti-Patterns**: What the agent must avoid.

Keep agent prompts focused. One role per agent. If an agent needs domain knowledge beyond its prompt, that knowledge lives in a skill -- not embedded in the agent definition.

---

## Skill Definition Format

Each skill is a directory under `skills/` containing a `SKILL.md` file.

### Frontmatter Schema

```markdown
---
name: skill-name
description: >-
  When to invoke this skill. Used by @agent-skill-router to match
  user intent to relevant skills. Be specific about trigger keywords
  and use cases.
globs:                     # optional — file patterns that trigger this skill
  - "**/*.py"
  - "**/Dockerfile"
---
```

### Frontmatter Fields

| Field | Required | Description |
|-------|----------|-------------|
| `name` | Yes | Unique skill identifier. Matches directory name. |
| `description` | Yes | When this skill should be activated. Skill-router reads this. |
| `globs` | No | File patterns — if current file matches, skill is auto-suggested. |
| `upstream` | No | Version-lock block for skills documenting third-party tools (see "Patrón: skills version-locked" below). |

### Patrón: skills version-locked para tools externas

Skills que documentan APIs/SDKs/frameworks de terceros (langchain, langgraph,
deep-agents, anthropic-sdk, langsmith, mcp-development, framework-selection,
etc.) son vulnerables a una clase específica de drift: el upstream cambia,
los ejemplos en el SKILL.md quedan stale, ARCA lo descubre cuando un agente
copia un patrón obsoleto a producción.

Inspirado en el patrón `agent-browser skills get core` de vercel-labs/agent-browser
(que sirve contenido version-locked dinámicamente desde el CLI). ARCA mantiene
contenido estático en SKILL.md pero anota explícitamente la versión upstream
cubierta + fecha de última verificación, de modo que un audit periódico cace
el drift antes de que envenene producción.

#### Frontmatter `upstream` block

```yaml
upstream:
  package: <pip/npm package name>
  language: <python|typescript|rust|...>
  version_pin: "<package>>=<min-version>"
  models_covered:                # solo si la skill cubre LLM models
    - claude-opus-4-8
    - claude-sonnet-4-6
  last_verified: "YYYY-MM-DD"   # fecha ISO del último diff vs source_of_truth
  source_of_truth: <URL>         # docs oficiales upstream
  drift_check: |
    <una línea por trigger>
    <procedimiento de re-verificación>
```

#### Skills target (17 candidatas a migrar)

`anthropic-sdk` (seminal, ya migrada en 2026-05-03), `langchain`,
`langchain-fundamentals`, `langchain-rag`, `langchain-middleware`,
`langchain-dependencies`, `langgraph`, `langgraph-fundamentals`,
`langgraph-human-in-the-loop`, `langgraph-persistence`, `deep-agents-core`,
`deep-agents-memory`, `deep-agents-orchestration`, `langsmith`,
`mcp-development`, `framework-selection`, `claude-api`.

#### Disparadores de re-verificación

- **Tiempo**: > 90 días desde `last_verified` → flag amarillo en `claude-config-audit`.
- **Eventos upstream**: nuevo release mayor del package, deprecación de método/endpoint usado en ejemplos, cambio de modelo en la familia (4.x → 4.7 hoy).
- **Hot-path bug**: si un agente copia un patrón del SKILL.md y rompe en producción → re-verificación inmediata + bump `last_verified`.

#### Procedimiento de re-verificación

1. Abrir `source_of_truth` URL del frontmatter.
2. Diff visual contra los ejemplos del SKILL.md body.
3. Aplicar correcciones puntuales — NO rewriting completo a menos que el upstream haya cambiado paradigma.
4. Bumpear `last_verified` a fecha ISO de hoy.
5. Si cambió `models_covered` o `version_pin`, actualizar.
6. Regenerar `SKILL_INDEX.json` + `docs/SKILLS.md` (`bash scripts/build-skill-index.sh && bash scripts/regen-skills-doc.sh`).
7. Commit con mensaje `docs(skills): re-verify <skill-name> against upstream <version>`.

### Skill Body Structure

```markdown
# Skill Title

## Overview / Stack Table
Brief intro, version table, or framework comparison.

## Core Concepts
Detailed sections with code examples. Each concept gets:
- Explanation (2-3 sentences)
- Code example (complete, runnable)
- Common variations

## Decision Guide
"When to use what" table or flowchart.

## Anti-Patterns
Table with: anti-pattern | why it fails | fix.

## References
Links to official docs, repos, specs.
```

### How Skills Are Loaded

Skills are NOT embedded in agent prompts. They are lazy-loaded:

1. User sends a message or task is delegated to an agent.
2. `@agent-skill-router` analyzes the task and selects up to 3 relevant skills.
3. Selected skill content is injected into the specialist agent's context.
4. After the task, skill content is discarded (not persisted in conversation).

This keeps agent prompts small and skill knowledge current.

---

## Hooks System

Hooks are deterministic shell scripts that fire at specific points in the Claude Code lifecycle. They are NOT LLM-powered -- they are fast, predictable guardrails.

### Hook Types

| Hook | When It Fires | Use Case |
|------|---------------|----------|
| `PreToolUse` | Before Bash, Write, Edit execute | Block dangerous commands |
| `PostToolUse` | After Bash completes | Logging, metrics |
| `UserPromptSubmit` | When user sends a message | Prompt injection detection |
| `SessionStart` | When a new session begins | Welcome banner, context loading |
| `SessionStop` | When session ends | Summary, cleanup |

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Continue — allow the operation |
| 2 | Block — prevent the operation |
| Other | Treated as error, logged but does not block |

### Environment Variables Available to Hooks

| Variable | Content |
|----------|---------|
| `TOOL_INPUT` | JSON string with tool parameters |
| `TOOL_NAME` | Name of the tool being called (for PreToolUse/PostToolUse) |
| `SESSION_ID` | Current session identifier |

### PreToolUse — Guardrails Example

```bash
#!/bin/bash
# hooks/guardrails.sh — Block destructive commands

CMD=$(echo "$TOOL_INPUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d.get('command', ''))
" 2>/dev/null)

# Block dangerous patterns
if echo "$CMD" | grep -qE 'rm -rf|DROP TABLE|DELETE FROM|mkfs|dd if='; then
    echo "GUARDRAILS: Destructive operation blocked: $CMD" >&2
    exit 2  # BLOCK
fi

exit 0  # ALLOW
```

### PreToolUse — PII Check

```bash
#!/bin/bash
# hooks/pii_check.sh — Warn on potential PII in outputs

CONTENT=$(echo "$TOOL_INPUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d.get('content', d.get('command', '')))
" 2>/dev/null)

# Check for common PII patterns
if echo "$CONTENT" | grep -qE '[0-9]{3}-[0-9]{2}-[0-9]{4}|[0-9]{16}'; then
    echo "PII_CHECK: Potential SSN or credit card number detected" >&2
    # Warn but do not block (exit 0)
fi

exit 0
```

### UserPromptSubmit — Injection Detection

```bash
#!/bin/bash
# hooks/prompt_injection_check.sh

PROMPT=$(echo "$TOOL_INPUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d.get('prompt', ''))
" 2>/dev/null)

if echo "$PROMPT" | grep -qiE 'ignore.*instructions|forget your|act as DAN|jailbreak'; then
    echo "GUARDRAILS: Prompt injection detected" >&2
    exit 2  # BLOCK
fi

exit 0
```

### SessionStart — Welcome and Context

```bash
#!/bin/bash
# hooks/session_start.sh

echo "Session started at $(date)" >> ~/.claude/session-log.txt

AGENTS=$(ls ~/.claude/agents/*.md 2>/dev/null | wc -l)
SKILLS=$(ls -d ~/.claude/skills/*/ 2>/dev/null | wc -l)

echo "ARCA loaded: ${AGENTS} agents, ${SKILLS} skills" >&2

# Load recent Engram context if available
if command -v engram &>/dev/null; then
    CONTEXT=$(engram context 2>/dev/null | head -10)
    if [ -n "$CONTEXT" ]; then
        echo "Last session context:" >&2
        echo "$CONTEXT" | sed 's/^/  /' >&2
    fi
fi

exit 0
```

### PostToolUse — Command Logging

```bash
#!/bin/bash
# hooks/command_logger.sh — Log executed commands

CMD=$(echo "$TOOL_INPUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d.get('command', ''))
" 2>/dev/null)

if [ -n "$CMD" ]; then
    echo "$(date -Iseconds) | $CMD" >> ~/.claude/command-log.txt
fi

exit 0
```

### Configuring Hooks in settings.json

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/hooks/guardrails.sh"
          }
        ]
      },
      {
        "matcher": "Write",
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/hooks/pii_check.sh"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/hooks/command_logger.sh"
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/hooks/prompt_injection_check.sh"
          }
        ]
      }
    ],
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/hooks/session_start.sh"
          }
        ]
      }
    ]
  }
}
```

---

## Slash Commands

Custom slash commands are Markdown files in `commands/`. They define reusable workflows invoked with `/command-name`.

### Command Format

```markdown
---
description: Short description shown in command palette.
---
Instruction body. $ARGUMENTS is replaced with user input after the command.

Example: /ml-new image classifier
$ARGUMENTS = "image classifier"
```

### Command Examples

**`commands/ml-new.md`** -- Start full ML pipeline:
```markdown
---
description: Start ML pipeline from C1 Discovery. Usage: /ml-new <objective>
---
Start the ML pipeline for: $ARGUMENTS

Execute in order:
1. @agent-token-optimizer -- compress initial context
2. @agent-project-planner -- elicit business/user/system/ML requirements + backlog Jira/Scrum
3. Present requirements doc + sprint plan to ⟦ user_name ⟧ for approval before continuing

Format: [C1 DISCOVERY] -> @agent-project-planner -> ⟦ user_name ⟧ approves
```

**`commands/review-pr.md`** -- Review a pull request:
```markdown
---
description: Review a GitHub PR. Usage: /review-pr <PR-URL>
---
Review this pull request: $ARGUMENTS

1. Fetch PR diff and description
2. Analyze for: correctness, security, performance, style
3. Provide structured review with severity levels
```

**`commands/diagnose.md`** -- Debug an issue:
```markdown
---
description: Diagnose a bug or error. Usage: /diagnose <error description>
---
Diagnose this issue: $ARGUMENTS

1. Reproduce or locate the error
2. Identify root cause
3. Propose fix with minimal blast radius
4. If fix is unclear, ask clarifying questions before proceeding
```

### Command Best Practices

| Practice | Rationale |
|----------|-----------|
| Keep instructions under 200 words | Commands should trigger workflows, not embed full prompts |
| Use $ARGUMENTS for user input | Standard variable substitution |
| Reference agents with @agent-name | Enables delegation protocol |
| Include expected output format | Consistency across invocations |
| One workflow per command | Composability over monoliths |

---

## Worktree Isolation

Agents with `isolation: worktree` run in a separate git worktree, creating their own branch automatically.

### When to Use Worktree Isolation

| Scenario | Use Worktree | Why |
|----------|-------------|-----|
| Long-running refactor | Yes | Avoid blocking main branch work |
| Parallel feature work | Yes | Independent branches, merge via PR |
| Quick code fix | No | Overhead not worth it for small changes |
| Read-only analysis | No | No file modifications needed |
| Destructive experiments | Yes | Isolated sandbox, easy to discard |

### How It Works

1. Claude Code detects `isolation: worktree` in agent frontmatter.
2. A new worktree is created: `.claude/worktrees/<branch-name>/`.
3. Agent operates in the worktree directory, not the main tree.
4. On completion:
   - If changes exist: create a PR for review.
   - If no changes: clean up the worktree automatically.

### Branch Naming Convention

```
feature-<task>      # New features
fix-<bug>           # Bug fixes
refactor-<module>   # Refactoring
experiment-<name>   # Experimental work (may be discarded)
```

### Manual Worktree Usage

```bash
# Launch Claude Code in a worktree
claude --worktree feature-new-skill

# List active worktrees
git worktree list

# Clean up a worktree
git worktree remove .claude/worktrees/feature-new-skill
```

### Gitignore

Add to `.gitignore` of every project using worktrees:
```
.claude/worktrees/
```

---

## Delegation Protocol

ARCA follows a strict delegation chain to manage context and cost.

### The Chain

```
1. @agent-token-optimizer    (compress context to ≤670 tokens)
       |
2. @agent-skill-router       (select max 3 relevant skills)
       |
3. Specialist agent           (with compressed context + selected skills)
       |
4. @agent-token-optimizer    (compress output to ≤200 tokens before Engram save)
```

### Why This Order Matters

| Step | Purpose | Token Impact |
|------|---------|-------------|
| Token optimizer first | Prevents context rot in delegated tasks | ~80% reduction |
| Skill router before specialist | Loads only relevant knowledge, not entire skill library | Targeted injection |
| Specialist with compressed context | Focused execution, faster inference | Minimal noise |
| Token optimizer on output | Engram entries stay searchable and small | Long-term memory health |

### Delegation Example

```
User: "Add retry logic to the API client"

1. @agent-token-optimizer:
   Input: "Add retry logic to the API client in src/api/client.py.
           Current code uses httpx with no error handling."
   Output (≤670 tokens): "Task: add retry to src/api/client.py (httpx, no error handling)"

2. @agent-skill-router:
   Analyzes: "retry logic" + "API client" + "httpx"
   Selects: [production, python-init, testing]

3. @agent-python-specialist:
   Receives: compressed context + 3 skill contents
   Produces: implementation with retry decorator, tests, updated code

4. @agent-token-optimizer:
   Compresses output to ≤200 tokens for Engram:
   "Added exponential backoff retry to src/api/client.py.
    Max 3 retries, backoff_factor=2. Tests in tests/test_retry.py.
    Covers 429/500/502/503/504 status codes."
```

---

## Multi-Model Strategy

ARCA uses two model tiers post 2026-05-03 enterprise rewrite. The Haiku
tier was retired — under a flat-rate Claude plan (your plan/mo, no per-token
billing) the pricing pressure that motivated Haiku for routing
disappeared, and Sonnet 4.6 absorbed those roles with strictly better
quality.

### Model Assignments

| Tier | Model | Used For | Roster size |
|------|-------|----------|------------|
| **Mechanical** | Sonnet 4.6 | Routing, summarization, narration, mid-tier mechanical work | 8 agents |
| **Regulated-grade** | Opus 4.8 | Architecture, gate-keeping, ML/DL/AI engineering, red-team, alignment research, evaluation, T&S, deploy, governance | 41 agents |

### Agent-to-Model Mapping

```
Sonnet 4.6 (mechanical / utility, 8 agents):
  @agent-skill-router
  @agent-token-optimizer
  @agent-cost-analyzer
  @agent-code-narrator
  @agent-debt-detector
  @agent-docs-writer
  @agent-git-master
  @agent-arca-ambient-monitor

Opus 4.8 (regulated-grade, 41 agents — abridged):
  Architecture & gate-keeping:
    @agent-architect-ai
    @agent-chief-architect
    @agent-code-critic
    @agent-math-critic
    @agent-maintainability-engineer
    @agent-data-validator
    @agent-model-evaluator
    @agent-tester
    @agent-project-planner

  ML/DL/AI engineering:
    @agent-ml-engineer
    @agent-dl-engineer
    @agent-ai-engineer
    @agent-distributed-training-engineer
    @agent-data-engineer
    @agent-data-scientist
    @agent-rag-engineer
    @agent-agent-engineer
    @agent-gpu-engineer
    @agent-perf-engineer
    @agent-mlops-engineer

  AI Safety Research (added 2026-05-03):
    @agent-alignment-researcher
    @agent-interpretability-researcher
    @agent-evals-engineer
    @agent-trust-and-safety-engineer

  Production & deploy:
    @agent-deployment
    @agent-devops
    @agent-aws-engineer
    @agent-frontend-ai
    @agent-monitoring
    @agent-ai-production-engineer
    @agent-api-designer

  Security & red team:
    @agent-ai-red-teamer
    @agent-htb-orchestrator
    @agent-htb-recon
    @agent-cve-hunter
    @agent-credential-hunter
    @agent-exploit-executor
    @agent-flag-validator

  Misc Opus:
    @agent-prompt-engineer
    @agent-python-specialist
    @agent-sensei
```

### Why Two-Tier Matters

- Under MAX flat-rate, the marginal token is free; the bottleneck is
  throughput and quality, not per-token cost.
- Promoting agents to Opus 4.8 where the work justifies it became the
  correct trade-off for any role that touches a regulated artifact
  (ADR, model card, deploy plan, fairness audit, jailbreak detector).
- Sonnet 4.6 retains routing and mechanical work where a wrong answer
  is recoverable by the next reviewer — preserves tier diversity (the
  test invariant `Sonnet >= 1` exists for exactly this reason).

---

## Settings.json Structure

### Full Structure Reference

```json
{
  "permissions": {
    "allow": [
      "Bash(git:*)",
      "Bash(python3:*)",
      "Bash(npm:*)",
      "mcp__fetch__fetch",
      "mcp__github__get_file_contents"
    ],
    "deny": [
      "Bash(rm -rf /)",
      "Bash(curl * | bash)"
    ]
  },
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/hooks/guardrails.sh"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/hooks/command_logger.sh"
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/hooks/prompt_injection_check.sh"
          }
        ]
      }
    ],
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/hooks/session_start.sh"
          }
        ]
      }
    ]
  },
  "mcpServers": {
    "engram": {
      "command": "npx",
      "args": ["-y", "@anthropic/engram-mcp"]
    },
    "github": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-github"],
      "env": {
        "GITHUB_TOKEN": "${GITHUB_TOKEN}"
      }
    },
    "fetch": {
      "command": "npx",
      "args": ["-y", "@anthropic/mcp-fetch"]
    },
    "custom-db": {
      "command": "python3",
      "args": ["/path/to/db_server.py"],
      "env": {
        "DATABASE_URL": "${DATABASE_URL}"
      }
    }
  },
  "env": {
    "LANGCHAIN_TRACING_V2": "true",
    "LANGSMITH_PROJECT": "arca-production"
  }
}
```

### Permissions Format

```json
{
  "permissions": {
    "allow": [
      "Bash(git:*)",
      "Bash(python3:*)",
      "Bash(/path/to/script.sh)",
      "mcp__server__tool",
      "Read",
      "Write",
      "Edit",
      "Glob",
      "Grep"
    ],
    "deny": [
      "Bash(rm -rf *)",
      "Bash(curl * | sh)"
    ]
  }
}
```

Permission patterns:
- `Bash(command:*)` -- allow command with any arguments
- `Bash(exact command)` -- allow only exact command string
- `mcp__<server>__<tool>` -- allow specific MCP tool
- Tool name alone (e.g., `Read`) -- allow all uses of that tool

### Settings File Precedence

```
.claude/settings.json         (project, committed to git)
  +
.claude/settings.local.json   (project, gitignored, personal overrides)
  +
~/.claude/settings.json       (user global)
  =
Final merged settings
```

MCP servers are merged from all levels. Permissions are merged (allow lists combined, deny takes precedence).

---

## Validation Script

ARCA includes `scripts/validate.sh` to check ecosystem consistency.

### What It Checks

```bash
#!/bin/bash
# scripts/validate.sh — Ecosystem consistency check

ERRORS=0

# 1. Every agent has required frontmatter
for agent in agents/*.md; do
    if ! grep -q "^name:" "$agent"; then
        echo "ERROR: $agent missing 'name' in frontmatter"
        ERRORS=$((ERRORS + 1))
    fi
    if ! grep -q "^model:" "$agent"; then
        echo "ERROR: $agent missing 'model' in frontmatter"
        ERRORS=$((ERRORS + 1))
    fi
done

# 2. Every skill directory has SKILL.md
for skill_dir in skills/*/; do
    if [ ! -f "${skill_dir}SKILL.md" ]; then
        echo "ERROR: ${skill_dir} missing SKILL.md"
        ERRORS=$((ERRORS + 1))
    fi
done

# 3. Hooks are executable
for hook in hooks/*.sh; do
    if [ ! -x "$hook" ]; then
        echo "WARNING: $hook is not executable"
    fi
done

# 4. Commands have description frontmatter
for cmd in commands/*.md; do
    if ! grep -q "^description:" "$cmd"; then
        echo "ERROR: $cmd missing 'description' in frontmatter"
        ERRORS=$((ERRORS + 1))
    fi
done

# 5. No duplicate agent names
DUPES=$(grep -h "^name:" agents/*.md | sort | uniq -d)
if [ -n "$DUPES" ]; then
    echo "ERROR: Duplicate agent names: $DUPES"
    ERRORS=$((ERRORS + 1))
fi

echo ""
if [ $ERRORS -eq 0 ]; then
    echo "Ecosystem validation passed."
else
    echo "Ecosystem validation FAILED with $ERRORS errors."
    exit 1
fi
```

---

## Decision Guide

| Need | Component | Where |
|------|-----------|-------|
| New specialist role | Agent | `agents/<name>.md` |
| Domain knowledge base | Skill | `skills/<name>/SKILL.md` |
| Reusable workflow shortcut | Command | `commands/<name>.md` |
| Safety guardrail | Hook (PreToolUse) | `hooks/<name>.sh` |
| Audit logging | Hook (PostToolUse) | `hooks/<name>.sh` |
| Input sanitization | Hook (UserPromptSubmit) | `hooks/<name>.sh` |
| External tool integration | MCP Server | `settings.json` mcpServers |
| Permission control | Settings | `settings.json` permissions |

---

## Anti-Patterns

| Anti-Pattern | Why It Fails | Fix |
|--------------|-------------|-----|
| Embedding skill content in agent prompts | Bloats context, stale knowledge | Skills are lazy-loaded by skill-router |
| Agent with 5+ responsibilities | Unfocused, poor output quality | One role per agent, delegate to others |
| LLM-powered hooks | Slow, non-deterministic, expensive | Hooks are shell scripts -- fast and predictable |
| Skipping token-optimizer before delegation | Context rot in specialist agents | Always compress first |
| Using opus model for routing/classification | Latency overhead + no quality gain on mechanical work | Use sonnet for routing/classification (haiku tier retired post 2026-05-03) |
| Hardcoding paths in hooks | Breaks on different machines | Use environment variables or relative to ARCA root |
| Commands that embed full instructions | Maintenance burden, duplication | Commands trigger workflows; agents + skills hold knowledge |
| No validation before sync | Broken agents/skills deployed to ~/.claude | Run validate.sh before sync.sh |
| Monolithic settings.json | Conflicts in team repos | Use settings.local.json for personal overrides |
| Worktree without cleanup | Disk space waste, stale branches | Auto-cleanup on task completion |
| Skipping skill-router and loading all skills | Context overflow, slow inference | Max 3 skills per task |
| Agent prompts longer than 1000 words | Diminishing returns, context pollution | Keep prompts focused, move knowledge to skills |

---

## References

- [Claude Code Documentation](https://docs.anthropic.com/en/docs/claude-code)
- [Claude Code Hooks](https://docs.anthropic.com/en/docs/claude-code/hooks)
- [Claude Code Settings](https://docs.anthropic.com/en/docs/claude-code/settings)
- [Claude Code MCP](https://docs.anthropic.com/en/docs/claude-code/mcp)
- [Claude Code Slash Commands](https://docs.anthropic.com/en/docs/claude-code/slash-commands)
- ARCA Repo: `~/Desktop/⟦ host_alias ⟧/.claude/`

<!-- ultrathink: extended thinking activo en esta skill/agent -->
