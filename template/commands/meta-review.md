---
context: fork
agent: Explore
description: Monthly meta-review (day 1, 7PM ⟦ timezone ⟧ via scheduled trigger). Aggregates 30-day telemetry, ADR additions, cycle closures, retrospective patterns. Writes to docs/meta-reviews/.
---

Run a meta-review of the ARCA ecosystem itself. This is the meta-agent — ARCA reviewing ARCA.

## Steps

### 1. Telemetry Analysis
Run the telemetry analyzer for the last 30 days:
```bash
python3 scripts/telemetry-analyzer.py --days 30
```

### 2. Skill Graph Analysis
Build and analyze the skill knowledge graph:
```bash
python3 scripts/build-skill-graph.py
```
Identify:
- Isolated skills (no relationships) — possible candidates for merging or removal
- Skill clusters that could be consolidated
- Missing relationships that should exist
- Domains with too many or too few skills

### 3. Agent Efficiency Review
For each agent in `agents/*.md` (total via `ls agents/*.md | wc -l`), evaluate:
- Read the agent definition from `agents/{name}.md`
- Cross-reference with telemetry (was it invoked this month?)
- Check if its model tier is appropriate (Opus for simple tasks = waste of speed)
- Check for prompt quality: clear identity, specific rules, no contradictions
- Flag agents with overlapping responsibilities

### 4. Hook Health
- List all hooks and their trigger events
- Identify hooks that fire too frequently (performance drag)
- Check hook state files in `~/.claude/state/` for anomalies

### 5. Pipeline Phase Assessment
- Review the 8-phase pipeline definition in CLAUDE.md
- Are all phases being used? Or are some always skipped?
- Are the gate criteria still relevant?

### 6. Evolution Proposals
Based on findings, propose:
- **New agents** that would fill gaps
- **Agent retirements** for unused or redundant agents
- **Skill merges** for overlapping skills
- **Hook optimizations** for performance
- **Pipeline adjustments** for workflow efficiency
- **New scheduled triggers** for automation opportunities

## Output

Write the meta-review to `briefings/meta-review.md` with format:

```markdown
# ARCA Meta-Review — {date}

## Health Score: N/10

## What's Working
- Top 3 things working well

## What's Not Working  
- Top 3 things that need attention

## Evolution Proposals
1. [HIGH] Proposal with rationale
2. [MEDIUM] Proposal with rationale
3. [LOW] Proposal with rationale

## Agent Report Card
| Agent | Used? | Tier OK? | Prompt Quality | Action |
|-------|-------|----------|----------------|--------|

## Skill Graph Insights
- Clusters, gaps, consolidation opportunities

## Recommendations
- Prioritized action list for next sprint
```

Save key findings to Engram. This is the self-improvement feedback loop.
