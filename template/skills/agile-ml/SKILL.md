---
name: agile-ml
description: >-
  Agile methodologies adapted for ML projects. Sprint planning with uncertainty,
  experiment-as-backlog-item, velocity tracking for ML teams, and ceremony adaptations.
  Use when managing ML project sprints, estimating ML tasks, or adapting Scrum for data science.
---

# Agile for ML Projects

## Why ML Needs Adapted Agile

Standard Agile assumes that work is decomposable into predictable units. Software features
can be estimated with reasonable confidence because the developer controls the outcome: write
code, it works or it doesn't, debug, ship. ML breaks this assumption in fundamental ways.

**The core tension:** In traditional software, effort correlates with outcome. In ML, effort
correlates with *learning*, not with success. An engineer can spend two weeks on an experiment
and the correct outcome is "this approach doesn't work" — that is *valuable*, not wasted.

### Where Standard Scrum Fails for ML

| Assumption | Traditional SW | ML Reality |
|---|---|---|
| Work is predictable | Yes — scope is defined | No — experiments may fail |
| Done means shipped | Feature in production | Model may not beat baseline |
| Estimation is reliable | ±20-30% typical | ±100% for research tasks |
| Dependencies are code | Libraries, APIs | Data availability, compute, labeling |
| Progress is linear | Build → test → ship | Explore → fail → pivot → succeed |
| Scope is fixed | Requirements doc | Hypothesis evolves with data |
| Definition of Done | Tests pass, deployed | Metrics above threshold, reproducible |

### When to Adapt vs When to Use Standard Scrum

- **Use standard Scrum:** Infrastructure work, API development, dashboard building, CI/CD
  pipelines, data pipeline plumbing — anything where the output is deterministic code.
- **Use adapted Agile:** Model development, feature engineering experiments, hyperparameter
  tuning, architecture search, data collection/labeling strategies, evaluation framework
  design — anything where the outcome is uncertain.
- **Hybrid (most common):** ML projects always have both types. Separate your backlog into
  deterministic and experimental tracks, apply the right methodology to each.

---

## Sprint Planning for ML

### Estimation Uncertainty Table

ML tasks carry fundamentally different levels of uncertainty. Use this table to calibrate
story point estimates and communicate risk to stakeholders.

| Task Type | Uncertainty | Point Multiplier | Time-Box Strategy |
|---|---|---|---|
| **Baseline implementation** | ±30% | 1.3x | Fixed deadline, reduce scope if needed |
| **Experiment / research** | ±100% | 2.0x | Strict time-box, fail fast |
| **Refactoring / cleanup** | ±20% | 1.2x | Standard estimation works |
| **Data pipeline** | ±50% | 1.5x | Depends on data source reliability |
| **Infrastructure / MLOps** | ±25% | 1.25x | Standard + buffer for tooling surprises |
| **Evaluation framework** | ±35% | 1.35x | Scope can grow as edge cases emerge |
| **Hyperparameter tuning** | ±80% | 1.8x | Time-box strictly, automate where possible |
| **Data labeling/collection** | ±60% | 1.6x | External dependency, buffer generously |

### Planning Poker Adaptations

1. **Use confidence intervals, not point estimates for experiments.** Instead of "this is
   5 points," say "this is 3-8 points depending on whether approach A works."

2. **Allocate experimentation budget per sprint.** Reserve 20-40% of sprint capacity for
   experiments that might not produce shippable artifacts. This is not slack — it is the
   core work of ML.

3. **Define kill criteria upfront.** Every experiment card must state: "If we haven't seen
   X improvement by day Y, we pivot to approach Z." This prevents runaway experiments.

4. **Separate must-have from nice-to-have experiments.** Sprint commitment includes only
   the deterministic work and the highest-priority experiment. Additional experiments are
   stretch goals.

### Sprint Capacity Planning

```
Sprint Capacity = Team Velocity × Sprint Length
ML Sprint Allocation:
  - 40% Deterministic work (pipelines, infrastructure, tests)
  - 40% Experimentation (model development, feature engineering)
  - 10% Technical debt / refactoring
  - 10% Ceremonies, reviews, documentation
```

---

## Experiment as Backlog Item

The fundamental unit of ML work is the **experiment**, not the **feature**. Traditional user
stories ("As a user, I want X so that Y") don't capture the nature of ML work. Use the
experiment card template instead.

### Experiment Card Template

```markdown
## Experiment: [EXP-XXX] <Title>

### Hypothesis
If we [change/implement/try X], then [metric Y] will [improve/change] by [Z amount]
because [reasoning based on data/literature/intuition].

### Success Criteria
- Primary metric: [metric] improves from [current] to [target] (minimum: [threshold])
- Secondary metric: [metric] does not degrade below [threshold]
- Statistical significance: p < [value] or confidence interval [range]

### Time-Box
- Maximum duration: [X days]
- Checkpoint at: [day Y — evaluate whether to continue]
- Kill criteria: If [metric] has not improved by [Z%] at checkpoint, STOP.

### Approach
1. [Step 1]
2. [Step 2]
3. [Step 3]

### Data Requirements
- Training data: [dataset, size, availability]
- Validation data: [dataset, size, availability]
- Test data: [holdout, size — DO NOT TOUCH until final evaluation]

### Compute Requirements
- Estimated GPU hours: [X]
- Memory requirements: [X GB VRAM / X GB RAM]
- Storage: [X GB for artifacts]

### Dependencies
- Blocked by: [other cards]
- Blocks: [other cards]
- Data dependency: [available / needs labeling / needs collection]

### Outcome (filled after experiment)
- Result: [SUCCESS / PARTIAL / FAILURE]
- Actual metric: [value]
- Learnings: [what we learned regardless of success/failure]
- Next steps: [productionize / iterate / pivot / abandon]
```

### Experiment States

```
PROPOSED → APPROVED → IN PROGRESS → CHECKPOINT → COMPLETED
                                        ↓
                                      KILLED (time-box exceeded or kill criteria met)
```

- **PROPOSED:** Hypothesis written, awaiting prioritization.
- **APPROVED:** Team agrees this is worth the time investment.
- **IN PROGRESS:** Actively running, consuming sprint capacity.
- **CHECKPOINT:** Mid-experiment evaluation against kill criteria.
- **COMPLETED:** Results documented, regardless of success or failure.
- **KILLED:** Stopped early based on predefined kill criteria. This is a valid and
  healthy outcome — not a failure of planning.

---

## Epic Types for ML Projects

ML projects decompose into four epic categories. Each has distinct story templates, estimation
characteristics, and Definition of Done criteria.

### 1. Data Epic

Covers data collection, cleaning, labeling, feature engineering, and pipeline construction.

**Story template:**
```
As a [data scientist / ML engineer],
I need [specific data transformation / pipeline / dataset],
so that [model training / evaluation / feature engineering] can proceed.

Acceptance criteria:
- [ ] Data schema validated against [spec]
- [ ] Pipeline handles [edge cases: nulls, duplicates, schema changes]
- [ ] Data quality metrics: completeness > [X%], freshness < [Y hours]
- [ ] Unit tests for transformations
- [ ] Documentation of data lineage
```

**Common stories:**
- Build ingestion pipeline for [source]
- Implement feature [X] from raw data
- Create train/validation/test split with stratification on [Y]
- Label [N] samples for [task] with inter-annotator agreement > [threshold]
- Build data validation checks for [pipeline stage]

### 2. Model Epic

Covers model architecture selection, training, hyperparameter tuning, and experiment management.

**Story template:**
```
As a [ML engineer / data scientist],
I want to [train / evaluate / tune] a [model type] for [task],
so that we can [achieve metric target / establish baseline / compare approaches].

Acceptance criteria:
- [ ] Experiment tracked in [MLflow / W&B / experiment tracker]
- [ ] Model artifacts registered in model registry
- [ ] Metrics: [primary] >= [threshold], [secondary] within [bounds]
- [ ] Training reproducible from config + seed
- [ ] Comparison against baseline documented
```

**Common stories:**
- Establish baseline with [simple model] on [dataset]
- Experiment: [EXP-XXX] — test hypothesis [description]
- Tune hyperparameters for [model] using [strategy]
- Implement [architecture] for [task]
- Run ablation study on [feature set / component]

### 3. Infrastructure Epic

Covers MLOps, training infrastructure, serving infrastructure, monitoring, and CI/CD for ML.

**Story template:**
```
As a [ML engineer / MLOps engineer],
I need [infrastructure component],
so that [training / serving / monitoring] is [automated / reliable / scalable].

Acceptance criteria:
- [ ] Infrastructure as code (Terraform / Pulumi / CloudFormation)
- [ ] Automated tests for infrastructure
- [ ] Monitoring and alerting configured
- [ ] Runbook for common failure modes
- [ ] Cost estimate documented
```

**Common stories:**
- Set up experiment tracking server
- Configure GPU training cluster with auto-scaling
- Build model serving endpoint with [latency SLA]
- Implement A/B testing framework
- Create model artifact storage with versioning

### 4. Evaluation Epic

Covers evaluation framework, metrics implementation, fairness analysis, and model validation.

**Story template:**
```
As a [data scientist / model evaluator],
I need [evaluation component],
so that we can [measure model quality / ensure fairness / validate robustness].

Acceptance criteria:
- [ ] Evaluation runs automatically on [trigger]
- [ ] Results stored and versioned
- [ ] Visualization / dashboard for stakeholder review
- [ ] Edge cases and failure modes documented
- [ ] Comparison against baseline included
```

**Common stories:**
- Implement [metric] computation pipeline
- Build fairness evaluation across [protected attributes]
- Create error analysis pipeline for [model]
- Design evaluation dataset for [edge case category]
- Implement statistical significance testing for model comparison

---

## Definition of Ready for ML Stories

A story is **Ready** for sprint inclusion only when all applicable criteria are met. Pulling
unready stories into a sprint is the number one cause of ML sprint failure.

### Checklist

| Criterion | Data Epic | Model Epic | Infra Epic | Eval Epic |
|---|---|---|---|---|
| Data source identified and accessible | REQUIRED | REQUIRED | N/A | REQUIRED |
| Data schema documented | REQUIRED | REQUIRED | N/A | REQUIRED |
| Success metrics defined with thresholds | REQUIRED | REQUIRED | REQUIRED | REQUIRED |
| Baseline exists for comparison | N/A | REQUIRED | N/A | REQUIRED |
| Compute requirements estimated | Optional | REQUIRED | REQUIRED | Optional |
| Dependencies resolved or time-boxed | REQUIRED | REQUIRED | REQUIRED | REQUIRED |
| Acceptance criteria written | REQUIRED | REQUIRED | REQUIRED | REQUIRED |
| Time-box defined (experiments only) | N/A | REQUIRED | N/A | N/A |
| Kill criteria defined (experiments only) | N/A | REQUIRED | N/A | N/A |
| Test data holdout secured (no leakage) | REQUIRED | REQUIRED | N/A | REQUIRED |

### Red Flags — Story Is NOT Ready

- "We'll figure out the data once we start" — NO. Data availability is a prerequisite.
- "We'll know the metric when we see the results" — NO. Define success before starting.
- "It depends on how the experiment goes" — Acceptable ONLY if kill criteria are defined.
- "We need to explore first" — This IS a valid story, but frame it as a time-boxed spike
  with explicit deliverables (a document, a decision, a prototype — not "understanding").

---

## Definition of Done for ML

### Model Stories

- [ ] Experiment tracked with all hyperparameters, metrics, and artifacts logged
- [ ] Model registered in model registry with version tag
- [ ] All unit tests pass (data processing, feature engineering, model inference)
- [ ] Integration tests pass (end-to-end pipeline)
- [ ] Primary metric meets or exceeds defined threshold
- [ ] Secondary metrics within acceptable bounds
- [ ] No data leakage verified (train/test separation audit)
- [ ] Results reproducible from committed config + fixed seed
- [ ] Experiment card updated with outcome and learnings
- [ ] Code reviewed by at least one team member
- [ ] Technical debt documented if any shortcuts were taken

### Data Stories

- [ ] Pipeline runs end-to-end without manual intervention
- [ ] Data quality checks pass (completeness, freshness, schema validation)
- [ ] Unit tests for all transformations
- [ ] Edge cases handled (nulls, duplicates, schema drift)
- [ ] Data lineage documented
- [ ] Performance benchmarked (throughput, latency)

### Infrastructure Stories

- [ ] Infrastructure as code committed and reviewed
- [ ] Automated tests pass
- [ ] Monitoring and alerting operational
- [ ] Runbook written for failure modes
- [ ] Cost within budget estimate (±20%)

---

## Velocity Tracking for ML Teams

### The Problem with Single-Track Velocity

ML teams that track a single velocity number produce meaningless metrics. A sprint with
three successful experiments and no infrastructure work looks identical to a sprint with
zero experiments and lots of pipeline building. The velocity number tells you nothing about
what actually happened.

### Multi-Track Velocity

Track velocity separately across three lanes:

```
Total Velocity = Infra Velocity + ML Velocity + Data Velocity

Sprint N:
  Infra: 15 pts (pipelines, serving, CI/CD)
  ML:     8 pts (experiments, model work)
  Data:  10 pts (feature engineering, labeling)
  Total: 33 pts
```

### Outlier Exclusion for Experiments

Experiments introduce high variance into velocity. A single experiment can consume 13 points
one sprint and 2 points the next, depending on whether it succeeds or gets killed early.

**Strategy:** Use a trailing median (not mean) over 4-6 sprints for ML velocity. Exclude
the highest and lowest sprint from the calculation. This gives a more stable planning
baseline.

```
ML Velocity (6-sprint window):
  Sprint 1:  5 pts
  Sprint 2: 13 pts  ← exclude (max)
  Sprint 3:  8 pts
  Sprint 4:  2 pts  ← exclude (min)
  Sprint 5:  7 pts
  Sprint 6:  9 pts

Planning velocity = median(5, 8, 7, 9) = 7.5 pts
```

### Velocity Dashboard Metrics

- **Throughput by lane:** Points completed per sprint per lane (infra/ML/data)
- **Experiment success rate:** Percentage of experiments that meet success criteria
- **Kill rate:** Percentage of experiments killed at checkpoint (healthy range: 20-40%)
- **Carry-over rate:** Stories carried from one sprint to next (target: < 15%)
- **Lead time by type:** Days from story creation to completion, segmented by epic type
- **Cycle time for experiments:** Days from experiment start to documented outcome

---

## Ceremony Adaptations

### Daily Standup — "What Did the Model Learn?"

Traditional: What did I do? What will I do? Any blockers?

**ML Adaptation:**

1. **What did I learn yesterday?** (Not "what did I do" — learning is the output)
   - "The model converges faster with learning rate 3e-4 but overfits after epoch 5"
   - "Feature X has 40% missing values — more than expected"
   - "Data pipeline handles 10K records/sec, need 50K for production"

2. **What experiment/task am I running today?**
   - Include expected duration if running long training jobs
   - Flag if a checkpoint evaluation is coming up

3. **Any blockers or kill criteria approaching?**
   - "GPU cluster at 90% utilization, my job is queued"
   - "Approaching checkpoint on EXP-042 — need to evaluate tomorrow"
   - "Waiting on labeled data from vendor, ETA unknown"

### Sprint Review — "Demo Metrics, Not Features"

Traditional sprint review demos working software. ML sprint review must demo *evidence*.

**Structure:**
1. **Metrics dashboard** — Show metric movements across experiments this sprint
2. **Experiment outcomes** — Each completed/killed experiment gets a 2-minute summary:
   hypothesis, what happened, what we learned
3. **Model comparison** — Visual comparison of current best vs baseline vs previous best
4. **Data insights** — Key data findings that affect model strategy
5. **Infrastructure progress** — What was automated, what monitoring was added
6. **Next sprint outlook** — What experiments are planned, what questions remain open

**Stakeholder communication tip:** Translate ML metrics into business impact. Don't say
"F1 improved from 0.82 to 0.87." Say "We reduced false negatives by 28%, meaning 28%
fewer fraudulent transactions will slip through."

### Sprint Retrospective — "Experiment Learnings"

Standard retro questions plus ML-specific additions:

- **What experiments succeeded and why?** Identify patterns in successful experiments.
- **What experiments failed and what did we learn?** Failed experiments are only wasted
  if we don't extract learnings.
- **Did our kill criteria work?** Were experiments killed at the right time, or did we
  spend too long on dead ends?
- **Were our estimates accurate?** Compare estimated vs actual for each task type.
  Update the uncertainty table based on real data.
- **Is our experiment backlog healthy?** Do we have enough hypotheses queued? Are they
  well-defined? Is the pipeline of ideas flowing?
- **Data surprises?** Did we discover data quality issues mid-sprint? How do we prevent
  this next time?

### Backlog Refinement — "Hypothesis Workshop"

Dedicate one refinement session per sprint specifically to generating and refining
experiment hypotheses. This is where the team collaborates on:

- Reviewing literature / competitor approaches for new ideas
- Analyzing error patterns from current model to identify improvement areas
- Brainstorming feature engineering ideas based on domain knowledge
- Prioritizing experiments by expected impact vs effort

---

## Impediment Patterns

Common ML-specific blockers and their mitigation strategies.

| Impediment | Frequency | Impact | Mitigation |
|---|---|---|---|
| **Data not ready** | Very common | Blocks model work | Maintain data readiness backlog; start data work 1 sprint ahead of model work |
| **Compute bottleneck** | Common | Delays training | Implement job queue with priorities; use spot instances; optimize batch sizes |
| **Experiment failed** | Expected | Consumes capacity | Kill criteria prevent runaway; have backup experiments ready |
| **Concept drift detected** | Periodic | Model degradation | Automated monitoring; retraining triggers; data freshness SLAs |
| **Labeling delays** | Common | Blocks evaluation | Buffer in timeline; use semi-supervised approaches; multiple labeling vendors |
| **Environment inconsistency** | Occasional | Irreproducible results | Docker containers; pinned dependencies; infrastructure as code |
| **Metric disagreement** | Occasional | Team misalignment | Define metrics in Definition of Ready; align with stakeholders in sprint planning |
| **GPU OOM errors** | Common | Wastes experiment time | Profile memory before long runs; gradient checkpointing; mixed precision |
| **Data leakage discovered** | Rare but critical | Invalidates results | Automated leakage detection in pipeline; code review checklist |
| **Stakeholder scope change** | Periodic | Sprint disruption | Protect sprint commitment; defer to next sprint; update product backlog |

### Escalation Protocol

1. **Day 1:** Engineer flags impediment in daily standup
2. **Day 2:** Scrum Master actively working to resolve
3. **Day 3:** If unresolved, escalate to Product Owner for priority decision
4. **Day 5:** If still unresolved, consider sprint scope adjustment

---

## Kanban vs Scrum: When to Use Which

### Research-Heavy Phase → Kanban

When the team is in exploration mode (early project phases, architecture search, extensive
feature engineering), Kanban is more appropriate because:

- Work items vary wildly in size and duration
- Priorities shift based on findings
- Strict sprint boundaries create artificial pressure to "finish" experiments
- WIP limits prevent overloading with too many parallel experiments

**Kanban board columns for ML research:**
```
Hypothesis → Ready → In Progress → Checkpoint → Analysis → Documented
                     (WIP: 3)                                (WIP: 2)
```

### Delivery-Heavy Phase → Scrum

When the team is in delivery mode (productionizing a validated model, building serving
infrastructure, operationalizing monitoring), Scrum is more appropriate because:

- Work is more predictable and decomposable
- Stakeholders need regular delivery cadence
- Sprint commitments create healthy accountability
- Velocity tracking becomes meaningful

### Hybrid Approach (Recommended)

Most ML teams should use a hybrid at all times:
- **Scrum** for the overall sprint cadence, ceremonies, and deterministic work
- **Kanban** for the experiment lane within the sprint (WIP-limited, no point estimates
  for individual experiments, just a time-box budget)

---

## Sprint Template: 4-Sprint Plan for a Classification Project

### Sprint 1 — Foundation

**Goal:** Establish baseline and infrastructure

| Story | Type | Points | Notes |
|---|---|---|---|
| Set up experiment tracking (MLflow) | Infra | 5 | |
| Build data ingestion pipeline | Data | 8 | |
| Create train/val/test split | Data | 3 | Stratified on target |
| EDA and data quality report | Data | 5 | |
| Implement evaluation framework | Eval | 5 | Precision, recall, F1, AUC |
| Train baseline (logistic regression) | Model | 3 | This IS the baseline |
| **Total** | | **29** | |

### Sprint 2 — Experimentation

**Goal:** Beat baseline with at least one approach

| Story | Type | Points | Notes |
|---|---|---|---|
| EXP-001: Gradient boosting with raw features | Model | 5 | Time-box: 3 days |
| EXP-002: Feature engineering — interaction terms | Data/Model | 8 | Time-box: 4 days |
| EXP-003: Neural network baseline | Model | 5 | Time-box: 3 days |
| Build feature store for engineered features | Infra | 5 | |
| Implement data validation checks | Data | 3 | Great Expectations or similar |
| Error analysis on baseline predictions | Eval | 5 | |
| **Total** | | **31** | Expect 1-2 experiments to fail |

### Sprint 3 — Optimization

**Goal:** Optimize best approach, harden pipeline

| Story | Type | Points | Notes |
|---|---|---|---|
| Hyperparameter tuning for best model | Model | 8 | Optuna / Ray Tune |
| EXP-004: Ensemble of top 2 approaches | Model | 5 | Time-box: 3 days |
| Fairness evaluation across protected groups | Eval | 5 | |
| Build training pipeline (automated) | Infra | 8 | |
| Implement model versioning and registry | Infra | 3 | |
| Create model card documentation | Eval | 3 | |
| **Total** | | **32** | |

### Sprint 4 — Productionization

**Goal:** Deploy model with monitoring

| Story | Type | Points | Notes |
|---|---|---|---|
| Build serving endpoint | Infra | 8 | Latency < 100ms p99 |
| Implement A/B test framework | Infra | 5 | |
| Build monitoring dashboard | Infra | 5 | Drift detection, latency, errors |
| Load testing and optimization | Infra | 5 | |
| Create runbook for model operations | Eval | 3 | |
| Final model evaluation on holdout test set | Eval | 3 | FIRST time touching test set |
| Stakeholder demo preparation | — | 2 | |
| **Total** | | **31** | |

---

## Anti-Patterns

### 1. Treating Experiments as Features

**Symptom:** Experiment stories are written as "Implement XGBoost model" with a Definition
of Done that says "model deployed."

**Problem:** This conflates research (uncertain) with delivery (deterministic). The team
feels pressure to "succeed" at every experiment, leading to either inflated timelines or
abandoned experiments reported as failures.

**Fix:** Use experiment cards with hypothesis/kill-criteria structure. An experiment that
is killed on time and with documented learnings is a SUCCESS, not a failure.

### 2. No Time-Box on Experiments

**Symptom:** "We're still working on EXP-007, it's been three sprints but we're close."

**Problem:** Without time-boxes, experiments consume unlimited capacity. The sunk cost
fallacy keeps teams investing in diminishing returns. Three sprints on one experiment means
six other experiments never ran.

**Fix:** Every experiment has a maximum duration and checkpoint. At checkpoint, evaluate
against kill criteria. Kill early and often — it frees capacity for new hypotheses.

### 3. Skipping Retro on Failures

**Symptom:** Failed experiments are quietly closed. No discussion, no learnings extracted.

**Problem:** The team loses the most valuable output of failed experiments: knowledge about
what doesn't work and why. Without this knowledge, future experiments may repeat the same
mistakes.

**Fix:** Failed experiments get MORE retro time, not less. Create an "experiment learnings"
document that the team maintains. Every failed experiment adds an entry.

### 4. Point Estimates for Research

**Symptom:** "How many points is this experiment?" "Five." "Are you sure?" "Yes."

**Problem:** Point estimates for research tasks create an illusion of certainty. When the
estimate is wrong (it will be), the team either overruns the sprint or artificially closes
incomplete work.

**Fix:** Use confidence intervals for experiments. "3-8 points, most likely 5." Track actuals
to calibrate. Use time-boxes as the primary planning mechanism, not points.

### 5. Single Backlog Without Type Distinction

**Symptom:** Infrastructure stories compete with experiment stories in a single prioritized
list. "Should we fix the data pipeline or run another experiment?"

**Problem:** These are not comparable. Infrastructure is an investment in future velocity;
experiments are the core ML work. Comparing them on a single axis leads to either
infrastructure debt (all experiments) or stalled research (all infrastructure).

**Fix:** Maintain separate lanes with allocated capacity. Each sprint budgets capacity for
infra, experiments, and data work independently.

### 6. No Baseline Before Experimenting

**Symptom:** Team jumps straight to complex models without establishing a simple baseline.

**Problem:** Without a baseline, there is no way to measure improvement. Teams build
elaborate architectures that perform 2% better than logistic regression — but they don't
know that because they never ran logistic regression.

**Fix:** Sprint 1 always includes a baseline model. Every subsequent experiment is measured
against it. The baseline is sacred — it is the floor, not the ceiling.

### 7. Ignoring Data Work in Sprint Planning

**Symptom:** Sprint planning focuses on model work. Data pipeline stories are "stretch goals"
or "we'll get to it."

**Problem:** Model work depends on data quality and availability. Skipping data work creates
invisible technical debt that surfaces as poor model performance, irreproducible results, or
pipeline failures in production.

**Fix:** Data work gets first-class citizenship in sprint planning. Data stories must meet
Definition of Ready. Data pipeline health is a sprint review metric.

### 8. Demo-Driven Development

**Symptom:** Team optimizes for impressive sprint review demos rather than systematic progress.
Cherry-picked results, single-example demos, no statistical rigor.

**Problem:** Stakeholders get a distorted view of progress. Decisions are made based on
anecdotes, not metrics. When the model reaches production, reality doesn't match the demos.

**Fix:** Sprint reviews show aggregate metrics, confidence intervals, and failure cases.
Every demo includes "here's where the model fails" alongside "here's where it succeeds."
