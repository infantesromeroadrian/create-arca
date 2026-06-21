---
context: fork
agent: Explore
description: Analyze ~/.claude/telemetry.jsonl over N days (default 7). Surfaces hot paths, agent invocation patterns, preflight compliance rate, cost attribution, drift signals, unused agents.
---

Analyze ARCA telemetry data and generate actionable insights.

Run the telemetry analyzer:
```bash
python3 scripts/telemetry-analyzer.py --days ${1:-7}
```

If the script is not at `scripts/telemetry-analyzer.py`, check the repo root or `~/Desktop/⟦ host_alias ⟧/.claude/scripts/`.

After showing the report, provide:
1. Your interpretation of the top patterns
2. Specific actions to optimize cost or improve routing
3. Any agents/skills that should be reviewed

Save key insights to Engram for trend tracking.
