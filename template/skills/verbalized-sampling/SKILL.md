---
name: verbalized-sampling
description: Apply Verbalized Sampling (Zhang et al., 2026) when output diversity matters more than convergence — multi-option ADRs, requirements elicitation edge cases, hypothesis generation, creative writing, synthetic data. Prompts the model to verbalize a probability distribution over N candidate responses to circumvent mode collapse from RLHF typicality bias. Increases diversity 1.6-2.1x at inference time, training-free. SKIP for code fixes, gate verdicts, factual queries, or any task that must converge.
effort: medium
paths:
  - "**/adrs/**"
  - "**/architecture/**"
  - "**/requirements/**"
  - "**/hypotheses/**"
  - "**/briefings/**"
---

# Verbalized Sampling — mitigate LLM mode collapse

## What this is

A training-free, inference-time prompting strategy that asks the model to verbalize
a probability distribution over N candidate responses, rather than emit a single
"most likely" answer. Counters the typicality bias introduced by RLHF preference
data, where annotators systematically favor familiar text and the model collapses
to convergent outputs.

Source: Zhang, Yu, Chong, Sicilia, Tomz, Manning, Shi (Northeastern, Stanford, WVU,
2026). *Verbalized Sampling: How to Mitigate Mode Collapse and Unlock LLM Diversity.*
Project page (Website / Blog / Code links visible on the paper's title page);
arxiv preprint pending — update this skill when the canonical URL is available.

## When to apply

ACTIVATE when the task is one of:

- **Architecture decisions with multiple options** — ADRs from `@architect-ai`,
  trade-off analyses where the typical answer hides better alternatives.
- **Requirements elicitation edge cases** — `@project-planner` discovering
  user scenarios that anchor-bias misses.
- **Hypothesis generation** — `@data-scientist` proposing competing hypotheses
  before EDA narrows them.
- **Synthetic data and test cases** — `@tester` covering edge paths beyond
  happy-path defaults.
- **Creative writing and framing** — briefings, summaries, narrative angles.
- **Brainstorming with a single agent** — when `/voting-review-team` is overkill
  and you want diversity from one specialist.

SKIP when:

- **Bug fixes and code corrections** — must converge to one fix.
- **Gate verdicts** — `@code-critic`, `@math-critic`, `@debt-detector`,
  `@model-evaluator` must give a single, defensible decision.
- **Factual queries** — counts, status, lookups.
- **Pipeline gates** — C-cycle exit criteria are binary, not distributional.
- **Decisions with strict acceptance criteria** — promotion to main, deploy, etc.

## Prompt template

Replace a direct ask:

```
Generate <X>.
```

With a verbalized-sampling ask:

```
Generate N=<n> candidate responses for <X>, each with its corresponding
probability of being typical for the input distribution. Show the full
distribution. Favor responses where probability is between 0.05 and 0.20 to
prioritize diversity over typicality. After listing all N candidates with
their probabilities, recommend the top-3 by usefulness for <X>, NOT by
probability.
```

The decoupling between "probability" (typicality) and "recommendation"
(usefulness for the task) is what unlocks diversity. The model would otherwise
default to the highest-probability output.

## N calibration

| N | Use case | Token cost (approx) |
|---|---|---|
| 3 | Low-cost diversity (ADR with 3 options, briefing framings) | 1.5x baseline |
| 5 | Default — balanced diversity vs cost | 2.5x baseline |
| 10 | Maximal exploration (research, novel hypotheses) | 5x baseline |

Drop to N=3 when context window > 50% used, to avoid context rot.

## Probability interpretation

Verbalized probabilities are NOT calibrated against ground truth. Treat them as
relative ordering only:

- `prob > 0.30` → typical-mode candidate (the one the model would emit by default).
  Drop unless explicitly asked.
- `prob 0.05 to 0.20` → sweet spot for diversity. These are the candidates VS
  was designed to surface.
- `prob < 0.03` → degenerate or noise. Drop unless the task explicitly asks
  for outliers.

## Conflict and complementarity with `/voting-review-team`

Both attack output diversity but at different layers:

| Layer | VS | `/voting-review-team` |
|---|---|---|
| Source of diversity | Single agent verbalizes distribution | 3 specialist agents with different perspectives |
| Cost | N tokens out | 3 agents x 2 rounds |
| Best for | Diverse options inside one perspective | Diverse perspectives across roles |

**Combine them**: apply VS inside each teammate's round 1 of `/voting-review-team`.
Each reviewer surfaces N candidate findings instead of one, then the debate round
operates on a richer pool. Multiplies coverage at the cost of more tokens.

## Hard rules

- **Never apply VS to gate verdicts.** Gates must converge.
- **Never apply VS to factual recall.** Drift is a bug there, not a feature.
- **Document VS use in the artifact.** When an ADR or hypothesis was generated
  via VS, note it in the document so reviewers know the diversity is intentional.
- **No emojis in VS-generated outputs.** ARCA convention applies.
- **Verify probability ordering is monotonic.** A model that lists `[0.40, 0.05,
  0.15]` is hallucinating the distribution; reject and re-prompt.

## Caveats

- The paper is recent (2026); independent replication is still ongoing. Treat VS
  as a useful tool, not a verified production guarantee.
- Effect is stronger on larger models (Opus 4.8 > Sonnet 4.6 > Haiku 4.5). Don't
  expect the same diversity gain from a small model.
- Safety properties of the model are preserved per the paper, but verify
  empirically before relying on VS for sensitive content.

## Quick reference

| Action | Template |
|---|---|
| Plain ADR | `Generate 3 architecture options for X with pros/cons.` |
| ADR + VS | `Generate N=5 candidate architectures for X, each with probability of being a typical answer. Recommend the top-3 by usefulness for our constraints, not by probability.` |
| Hypothesis set | `Generate N=10 competing hypotheses for the observed pattern in <data>, each with its typicality probability. Then list the 3 hypotheses with prob 0.05–0.15 that warrant investigation.` |
| Edge-case tests | `Generate N=10 test scenarios for <function>, each with probability of being the canonical happy-path test. Surface the 5 with lowest probability that still represent valid input.` |
