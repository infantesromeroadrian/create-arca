---
context: fork
agent: Explore
description: Weekly forensic audit — scans hook coverage, ADR drift, skill catalog integrity, telemetry health. Runs Sun 8PM ⟦ timezone ⟧ via scheduled trigger; manual via /guardian-audit.
---

Run a weekly guardian audit of the ARCA ecosystem. This is meant to run weekly (scheduled or manual).

## Steps

1. **Telemetry Analysis** — Read `~/.claude/telemetry.jsonl` and analyze:
   - Top 10 most-used tools (by count)
   - Top 5 most-invoked agents
   - Estimated token cost for the week (use pricing: Opus $15/$75, Sonnet $3/$15, Haiku $0.80/$4 per 1M tokens)
   - Error rate and most common error types
   - Average session duration and tool uses per session

2. **Agent Health** — Enumerate agents via `ls agents/*.md | wc -l` and for each:
   - Check valid YAML frontmatter
   - Identify agents never invoked this week (dead agents)
   - Flag agents with outdated model references

3. **Skill Freshness** — Enumerate skills via `ls -d skills/*/ | wc -l` and for each:
   - Identify skills never loaded this week
   - Check if any skill references deprecated APIs or outdated library versions
   - Use Context7 MCP to verify key library versions mentioned in skills are current

4. **Dependency Audit** — For active projects in ~/Desktop/⟦ host_alias ⟧/:
   - Run `pip audit` or `npm audit` where applicable
   - Flag critical CVEs
   - Check for outdated dependencies

5. **Ecosystem Integrity** — Run the validation suite:
   - Execute `scripts/validate.sh` if available
   - Check hook permissions (all .sh files executable)
   - Verify settings.json structure

## Output

Write the audit report to TWO locations:
1. `~/.claude/briefing/weekly-audit.md`
2. Obsidian note at `/Projects/ARCA/WeeklyAudit.md` via Obsidian MCP

Save key metrics to Engram for trend tracking.

Format as:
```markdown
# ARCA Weekly Audit — {date range}

## Resumen Ejecutivo
- 1-3 sentence summary of ecosystem health

## Uso
- Tool usage chart
- Agent invocation stats
- Cost estimate

## Alertas
- Dead agents/skills
- Security vulnerabilities
- Outdated dependencies

## Recomendaciones
- Top 3 actionable improvements
```
