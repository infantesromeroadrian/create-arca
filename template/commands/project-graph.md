---
context: fork
agent: Explore
description: Generate ARCA cross-project dependency graph. Detects shared utilities, ADR refs, hook invocations across agents/hooks/skills/commands. Output: docs/project-graph.{json,svg}.
---

Build and display the ARCA project knowledge graph.

Run the project graph builder:
```bash
python3 scripts/project-graph.py --output summary
```

If the script is not at `scripts/project-graph.py`, check the repo root or `~/Desktop/⟦ host_alias ⟧/.claude/scripts/`.

After showing the graph summary:
1. Highlight projects that need attention (active with dirty files, stale branches)
2. Note shared dependencies that could cause version conflicts
3. Suggest which dormant projects could be archived
4. If the user asks about a specific project, provide detailed context from the graph JSON at `~/.claude/briefing/project-graph.json`
