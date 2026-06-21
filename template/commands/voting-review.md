---
description: Run an emergent voting review with 3 parallel adversarial agents (Pragmatist, Architect, Adversary) synthesizing a consensus verdict.
---

Run an emergent voting review on the specified target. This spawns 3 independent agents with different perspectives that analyze the same code/problem in parallel, then synthesizes a consensus verdict.

## Usage
/voting-review <target> [--mode security|architecture|quality]

## Process

### Step 1: Spawn 3 agents in parallel with worktree isolation

Launch ALL THREE agents simultaneously using the Agent tool. Each MUST have `isolation: "worktree"` to work independently. Use a single message with 3 Agent tool calls.

**Agent 1 — The Pragmatist**
- Subagent type: `code-critic`
- Perspective: Production-focused. Looks for bugs, edge cases, performance issues, and anything that would break in production. Practical, not theoretical.
- Prompt: "You are the Pragmatist reviewer. Focus on: Will this work in production? Edge cases? Error handling? Performance bottlenecks? Data validation? Be specific with file:line references. Score 1-10 on production readiness. Target: {target}"

**Agent 2 — The Architect**  
- Subagent type: `chief-architect`
- Perspective: Structural analysis. SOLID principles, coupling, cohesion, scalability, maintainability. Long-term thinking.
- Prompt: "You are the Architect reviewer. Focus on: SOLID violations? Tight coupling? Scalability concerns? Technical debt being introduced? Abstraction quality? Be specific with file:line references. Score 1-10 on architectural quality. Target: {target}"

**Agent 3 — The Adversary**
- Subagent type: `ai-red-teamer`  
- Perspective: Attack surface. Security vulnerabilities, injection vectors, data exposure, auth bypass, supply chain risks.
- Prompt: "You are the Adversary reviewer. Focus on: Injection vectors? Auth/authz bypass? Data exposure? Secrets handling? Dependency vulnerabilities? OWASP Top 10 violations? Be specific with file:line references. Score 1-10 on security posture. Target: {target}"

### Step 2: Collect and synthesize

After all 3 agents complete, create a consensus report:

```markdown
# Voting Review — {target}

## Scores
| Perspective | Score | Key Finding |
|-------------|-------|-------------|
| Pragmatist  | N/10  | ... |
| Architect   | N/10  | ... |
| Adversary   | N/10  | ... |
| **Consensus** | **avg/10** | |

## Unanimous Findings (all 3 agree)
- List issues found by ALL reviewers

## Majority Findings (2 of 3 agree)
- List issues found by 2 reviewers

## Unique Findings (1 reviewer only)
- List issues found by only 1 reviewer (flag for manual review)

## Verdict
- APPROVED: avg ≥ 7 and no unanimous blockers
- CONDITIONAL: avg ≥ 5 or has majority findings
- REJECTED: avg < 5 or has unanimous blockers

## Action Items
- Prioritized list of fixes
```

### Step 3: Save to Engram

Save the verdict and key findings to Engram for trend tracking across reviews.

## Modes

- **security** (default for /voting-review): All 3 agents focus on security from different angles (script-kiddie, researcher, insider)
- **architecture**: All 3 focus on design quality from different angles (maintainer, scaler, newcomer)  
- **quality**: Mixed review as described above (pragmatist, architect, adversary)
