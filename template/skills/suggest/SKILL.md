---
name: suggest
description: Before any non-trivial action, enumerate which agents, skills, and MCPs are relevant. Prevents ARCA from defaulting to direct execution. Invoke automatically at task start or when ⟦ user_name ⟧ says /suggest, qué agente uso, qué skill hay para esto, or similar.
when_to_use: before starting ANY task that touches code, infra, architecture, security, git mutations, or research — to surface the right agents + skills + MCPs
argument-hint: "<task description>"
disable-model-invocation: false
user-invocable: true
allowed-tools: Read Grep Glob
model: sonnet
effort: low
paths:
  - "**/*"
---

# /suggest — Surface relevant agents, skills, and MCPs before acting

⟦ user_name ⟧ described the task: `$ARGUMENTS`

## Step 1: Classify the task

Read the task description and classify into one or more categories:
- `infra` (CLI install, Docker, K8s, Terraform, cloud)
- `ml` (training, model, data pipeline, feature engineering)
- `code` (Python, scripts, refactor, bug fix)
- `architecture` (design decisions, patterns, ADRs)
- `security` (audit, red team, pentest, CVE)
- `git` (commit, branch, merge, PR, push)
- `research` (web search, docs lookup, investigation)
- `docs` (README, writeup, documentation)
- `htb` (CTF, box, challenge)
- `redteam` (AI adversarial testing)

## Step 2: For each category, output recommendations

Format:

```
═══════════════════════════════════════════════════════
[SUGGEST] Task: <summary>
═══════════════════════════════════════════════════════

AGENTS:
  → @<agent-name> — <one-line reason>
  → @<agent-name> — <one-line reason>

SKILLS:
  → /<skill-name> — <one-line reason>
  → /<skill-name> — <one-line reason>

MCPs:
  → mcp__<name>__* — <one-line reason>

GATES REQUIRED:
  → @code-critic (if code produced)
  → @math-critic (if ML/DL/AI code)
  → @git-master (if git mutation)

PREFLIGHT:
  → @token-optimizer (compress context)
  → @skill-router (select max 3 skills)
═══════════════════════════════════════════════════════
```

## Step 3: Ask ⟦ user_name ⟧

> "Estas son mis recomendaciones para esta tarea. ¿Delego a <primary agent> o prefieres otro approach?"

## Rules

- NEVER output "no suggestions" — there is ALWAYS at least one relevant agent or skill
- If task is trivial (ls, grep, read a file) → say so explicitly: "Tarea trivial — ejecución directa OK, no requiere delegación"
- If task matches a pipeline activation → suggest the pipeline command (/ml-new, /htb-new, /redteam-new)
- Include MCPs when web search, browser, or platform operations are involved
- Include gates when code or architecture is produced
- Keep it SHORT — max 15 lines of output
