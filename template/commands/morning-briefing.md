---
description: Generate a morning briefing for ⟦ user_name ⟧. This is meant to run daily (scheduled or manual).
---

Generate a morning briefing for ⟦ user_name ⟧. This is meant to run daily (scheduled or manual).

## Steps

1. **GitHub Activity** — Use GitHub MCP to check:
   - Open PRs across repos (⟦ github_user ⟧)
   - New issues in active repos
   - Recent commits (last 24h) in repos with recent activity
   - Format: bullet list, most important first

2. **Calendar** — Use Google Calendar MCP to check:
   - Today's events and meetings
   - Tomorrow's important items
   - Format: timeline view

3. **Engram Context** — Search Engram for:
   - Unresolved blockers from recent sessions
   - Pending decisions waiting for input
   - Active project phases and next steps

4. **Kaggle** — Check active competitions:
   - Leaderboard position changes
   - Upcoming deadlines (<7 days)

5. **System Health** — Quick check:
   - Disk space on main partitions
   - GPU status (nvidia-smi)
   - Any failed services

6. **Ambient Highlights (últimas 24h)** — Read `briefings/ambient-YYYYMMDD.md`
   for yesterday AND today (if exist). Extract every line tagged `**HIGH**`
   or `**MEDIUM**`. Filter duplicates by subject. Cap at the 8 most
   relevant. If no files exist or all lines are LOW/SKIP → write
   `Sin señales relevantes.`

   Source: produced by `scripts/ambient-scan.py` (Track B Feature #1).

7. **ARCA Compliance Score** — Run `bash scripts/compliance-report.sh --today --score`
   (returns a single percentage). Also run `--today --json` to extract the
   violation list. Report:
   - Compliance score `XX.X%` (specialist delegations).
   - Count of violations (if any) grouped by missing preflight agent.
   - If score ≥95% → one line. If <95% → call out which agent failed most.

8. **Engram Nudges (semanal, Hermes-3 Idea 2)** — Read the latest weekly
   nudges file at `~/.claude/state/engram-nudges/<YYYY-W>.md`. Source:
   `~/.claude/scripts/engram-pattern-detector.sh` triggered Mondays 06:55
   by `engram-pattern-detector.timer`. If file exists:
   - Extract the top 3 nudge headings (lines starting with `## Nudge`).
   - Include the **Suggested action** line for each.
   - Title the section "Engram Nudges semanal".
   If no file or all nudges already actioned → "Sin nudges nuevos esta semana."

## Output

Write the briefing to TWO locations:
1. `~/.claude/briefing/latest.md` — consumed by session_start.sh hook
2. Obsidian note at `/Projects/ARCA/DailyBriefing.md` via Obsidian MCP (overwrite)

Format the briefing as:
```markdown
# ARCA Briefing — {date}

## Prioridades
- Top 3 items that need attention today

## GitHub
- PRs, issues, commits summary

## Calendario
- Today's schedule

## Ambient Highlights (últimas 24h)
- Lista de señales HIGH/MEDIUM desde briefings/ambient-*.md

## Compliance Score
- XX.X% specialist delegations compliant · violaciones: N

## Engram Nudges semanal
- Top 3 patterns detectados por Qwen local sobre observations recientes

## Proyectos Activos
- Status of each active project with phase

## Sistema
- Health status
```

Keep it concise — this should be readable in 60 seconds.
