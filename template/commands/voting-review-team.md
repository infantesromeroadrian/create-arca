---
description: Run an emergent voting review with 3 parallel adversarial agents in an agent team (with shared task list and inter-agent messaging) synthesizing a consensus verdict.
---

Run a voting review using **agent teams** (not isolated subagents). Three reviewers
work in a shared team with task list and mailbox, plus one debate round of peer
cross-confrontation. Validated through POC Sprint 1 + Sprint 2 (2026-04-25):
parallel analysis surfaces convergent findings, debate round produces score
adjustments under peer pressure and surfaces NEW findings absent from initial
reports.

Requires `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` to be exported.

## Usage
/voting-review-team `<target>`

## Process — parallel analysis + 1 debate round

### Step 1: Create the team

```
TeamCreate(
  team_name="voting-review-<short-id>",
  description="Adversarial review of <target>",
  agent_type="review-lead"
)
```

This provisions:
- `~/.claude/teams/voting-review-<short-id>/config.json`
- `~/.claude/tasks/voting-review-<short-id>/` (shared task list)

### Step 2: Create one task per perspective, all blocked on a shared "load target" task

```
TaskCreate({
  subject: "Load target context",
  description: "Read <target> and summarize its purpose, surface area, dependencies."
})
TaskCreate({ subject: "Pragmatist review", description: "..." })
TaskCreate({ subject: "Architect review", description: "..." })
TaskCreate({ subject: "Adversary review", description: "..." })
TaskUpdate(addBlockedBy=[load-task-id]) on each review task
```

### Step 2.5: Resolve Project Standards block (per ADR-056, gentle-pi judgment-day pattern)

Before spawning teammates, the lead resolves a compact "Project Standards" block specific to the target's surface area. This block is **injected verbatim into all 3 reviewer prompts** so reviewers cannot drift from project conventions because they "didn't know rule X". Standards come from three sources matched against target file paths:

1. **Applicable skills** — match target files against `skills/*/SKILL.md` activation rules; extract the `## Compact Rules` or equivalent section verbatim.
2. **Relevant ADRs** — grep `docs/adr/*.md` for ADR numbers cited in or near target files (git blame, comment annotations), plus ADRs explicitly tagged with the target's domain (security, performance, ml, agents).
3. **CLAUDE.md sections** — match target type to the applicable CLAUDE.md sections (e.g. code under `agents/` matches "Mandatory Code-Critic Gate" + "AI Slop Detection 19 signals" + "Mortal sins" + "Forbidden patterns").

Output: a single Markdown block ~300-500 tokens with structure:

```markdown
# Project Standards — <target>

## From skills/<applicable>/
<verbatim Compact Rules section, trimmed to relevance>

## From ADRs
- ADR-NNN: <one-line description>
- ADR-NNN: <one-line description>

## From CLAUDE.md
- AI Slop signals applicable: #N, #M, #P
- Mortal sins applicable: #N, #M
- Mandatory gates for this target type: math-critic / code-critic / ai-red-teamer / ...
```

If standards resolution finds nothing for the target (e.g. greenfield prototype), record `Standards Resolution: none — generic adversarial review only` in the verdict report. This is a degraded mode but not a failure.

### Step 3: Spawn 3 teammates in a single message

ALL three Agent invocations in **one** assistant message so they spawn concurrently. **Each prompt MUST include the Project Standards block resolved in Step 2.5 verbatim** (per ADR-056 — reviewers cannot claim "I didn't know rule X" because every applicable rule is in their prompt):

- **Pragmatist** — `subagent_type: code-critic`, `team_name: voting-review-<short-id>`,
  `name: Pragmatist`. Prompt: focus on production readiness, edge cases, error
  handling, performance. Score 1-10. Read team config to discover peers. **Prepend the Project Standards block from Step 2.5 to the prompt.**

- **Architect** — `subagent_type: chief-architect`, `team_name: voting-review-<short-id>`,
  `name: Architect`. Prompt: SOLID, coupling, cohesion, scalability, technical debt.
  Score 1-10. Read team config to discover peers. **Prepend the Project Standards block from Step 2.5 to the prompt.**

- **Adversary** — `subagent_type: ai-red-teamer`, `team_name: voting-review-<short-id>`,
  `name: Adversary`. Prompt: injection vectors, auth bypass, data exposure, secrets,
  OWASP Top 10. Score 1-10. Read team config to discover peers. **Prepend the Project Standards block from Step 2.5 to the prompt.**

Prompt template per reviewer:

```
[Project Standards block from Step 2.5, verbatim]

---

[Original role-specific prompt: Pragmatist / Architect / Adversary]

Target: <file or directory>

Hard rule: any finding you raise must reference the Project Standards block above by section name (e.g. "violates AI Slop signal #6" or "violates ADR-026 ml-code-store mandate"). Findings that don't map to a documented standard are downgraded to SUGGESTION, not WARNING.
```

Each teammate:
1. Claims its assigned task via TaskUpdate(owner=<own-name>)
2. Reads the target
3. Writes findings + score in plain text via SendMessage(to: review-lead, ...)
4. Marks task completed via TaskUpdate(status: completed)
5. Goes idle (normal)

### Step 3.5 (Sprint 2): Debate round

After all 3 teammates send their **initial** reports to the lead, the lead
forwards each peer's report to the other two via `SendMessage` and triggers a
single debate round.

For each teammate (peer P):

```
SendMessage(to: P, message: """
DEBATE ROUND — peer reports for cross-review.

Peer A (<other-name-1>): <verbatim text of A's initial report>

Peer B (<other-name-2>): <verbatim text of B's initial report>

Your task: read both reports. For each finding by A and B that touches your
domain (production / architecture / security), respond in plain text via
SendMessage(to: team-lead) with one of these annotations per finding:

  CONFIRM #N (A or B): your reasoning if you agree.
  REFINE #N (A or B): how you would tighten/restate the finding.
  REJECT #N (A or B): your counter-argument with file:line evidence.
  OUT_OF_SCOPE #N: this finding does not touch your perspective.

Then, list any NEW findings that emerged from reading the peers (label as
NEW#1, NEW#2, ...).

Hard rules:
- Do NOT modify your own initial findings unless a peer's argument forces
  it — say so explicitly with REFINE.
- Do NOT debate score numerically; debate findings.
- This is the only debate round. After this, no more SendMessage between peers.

End your response with REVISED SCORE: X/10 if your score moved, or
SCORE UNCHANGED: X/10 if it stayed.
""")
```

Each teammate processes the debate prompt, sends its annotated response back
to the lead, and goes idle again. The lead now has 3 initial reports plus 3
debate annotations.

**Hard cap: 1 debate round.** No further `SendMessage` between peers after
this. If a teammate tries to initiate further debate, the lead ignores it.

### Step 4: Lead synthesizes verdict

The lead (this command's caller) collects the three messages (delivered automatically),
deduplicates findings across reviewers, and emits a verdict report:

```markdown
# Voting Review (Team Edition) — <target>

## Scores
| Perspective | Score | Key Finding |
|---|---|---|
| Pragmatist | N/10 | ... |
| Architect | N/10 | ... |
| Adversary | N/10 | ... |
| **Consensus** | **avg/10** | |

## Unanimous Findings (all 3 agree)
## Majority Findings (2 of 3 agree)
## Unique Findings (1 reviewer only)

## Verdict
- APPROVED: avg ≥ 7 and no unanimous blockers
- CONDITIONAL: avg ≥ 5 or has majority findings
- REJECTED: avg < 5 or has unanimous blockers

## Action Items
- Prioritized list
```

### Step 5: Save to Engram

`mem_save(type=decision, ...)` with verdict, scores, top-3 findings.

### Step 6: Tear down

```
SendMessage(to: Pragmatist, message: {type: "shutdown_request"})
SendMessage(to: Architect, message: {type: "shutdown_request"})
SendMessage(to: Adversary, message: {type: "shutdown_request"})
# Wait up to 30s for each teammate to TaskUpdate(status: completed) and go
# idle. Past 30s, force TeamDelete() regardless — TeamDelete must succeed
# even if teammates are stuck. If TeamDelete fails (team-in-zombie state
# observed in POC):
#   rm -rf ~/.claude/teams/<team_name>
#   rm -rf ~/.claude/tasks/<team_name>
TeamDelete()
```

## Hard rules

- **Single team per session.** If a team exists already, abort and ask user.
- **Max 1 debate round (hard cap).** Beyond the single debate round, the lead
  ignores any further peer SendMessage and proceeds to synthesis.
- **All teammate SendMessage targets MUST be `team-lead`.** Peer-to-peer
  SendMessage is forbidden after round 1 ends; if a teammate sends a DM to
  another teammate during round 2, the lead drops it and surfaces it as a
  protocol violation in the verdict.
- **No mocked findings.** Every finding must reference `file:line` from the actual target.
- **No emojis.** All output respects ARCA conventions.
- **Preflight not required for teammates inside a team.** Team membership replaces
  per-call preflight (the Agent invocation IS the preflight at team-creation time).

## Comparison vs `/voting-review` (v1)

| Eje | v1 (subagents paralelos) | v2 (this — agent team) |
|---|---|---|
| Comunicación entre reviewers | None | Shared task list + mailbox |
| Visibility durante ejecución | Output del lead solo | Idle notifications + DM peer summaries |
| Debate | None | Sprint 2 (not yet) |
| Coste estimado | 3 subagent ctx | 3 team ctx + lead ctx (slightly higher) |
| Complejidad operativa | Baja | Media (TeamCreate/SendMessage/TeamDelete) |
| Blast radius si falla | Subagent error | Team in zombie state — must TeamDelete |
