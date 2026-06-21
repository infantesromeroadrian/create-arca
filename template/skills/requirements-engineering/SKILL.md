---
name: requirements-engineering
description: >-
  Requirements engineering for ML/AI projects. Elicitation techniques, requirement levels
  (Business/User/System/ML), user stories, ML problem statements, acceptance criteria,
  traceability, stakeholder mapping, and prioritization. Invoke when starting C1 Discovery, writing
  requirements docs, defining ML problem statements, or validating requirement completeness.
---

# Requirements Engineering for ML/AI Projects

## Overview

Requirements engineering is the disciplined process of discovering, documenting, validating,
and managing what a system must do and how well it must do it. In ML projects, this is where
most failures originate -- not in model architecture or hyperparameter tuning, but in
misunderstanding what the system should actually accomplish.

This skill covers the full lifecycle: from stakeholder identification through elicitation,
specification, validation, and traceability. Every technique is adapted for the unique
challenges of ML systems, where requirements must capture not just functional behavior but
data expectations, model performance thresholds, fairness constraints, and interpretability
needs.

```
"The hardest single part of building a software system is deciding precisely what to build."
 -- Fred Brooks, The Mythical Man-Month

"In ML, you must also decide what success looks like before you know if it is achievable."
 -- Adapted for ML practice
```

---

## Core Concepts

### 1. Stakeholder Mapping

Before eliciting requirements, identify who matters and how much influence they have.

#### Power/Interest Grid

```
                HIGH POWER
                    |
    +---------------+---------------+
    |               |               |
    |  Keep         |  Manage       |
    |  Satisfied    |  Closely      |
    |               |               |
    | (Executive    | (Product      |
    |  sponsor,     |  owner,       |
    |  legal/       |  domain       |
    |  compliance)  |  expert,      |
    |               |  end user     |
    |               |  champion)    |
    +---------------+---------------+
    |               |               |
    |  Monitor      |  Keep         |
    |  (Minimal     |  Informed     |
    |  effort)      |               |
    |               | (Dev team,    |
    | (Peripheral   |  QA, data     |
    |  departments) |  annotators)  |
    |               |               |
    +---------------+---------------+
                    |
                LOW POWER
      LOW INTEREST        HIGH INTEREST
```

#### Stakeholder Register Template

```markdown
| Stakeholder       | Role              | Power | Interest | Strategy        | Key Concerns              |
|--------------------|-------------------|-------|----------|-----------------|---------------------------|
| VP Engineering     | Executive Sponsor | High  | Low      | Keep Satisfied  | Budget, timeline, ROI     |
| Product Manager    | Product Owner     | High  | High     | Manage Closely  | User value, prioritization|
| Data Science Lead  | Technical Lead    | Med   | High     | Keep Informed   | Feasibility, accuracy     |
| End Users          | Consumers         | Low   | High     | Keep Informed   | Usability, trust          |
| Legal/Compliance   | Governance        | High  | Med      | Keep Satisfied  | GDPR, fairness, liability |
| Data Annotators    | Data Quality      | Low   | Med      | Monitor         | Annotation guidelines     |
```

---

### 2. Elicitation Techniques

No single technique captures all requirements. Use at least 3 techniques per project.

#### Interviews (Structured)

Best for: understanding domain context, uncovering hidden constraints, building rapport.

```markdown
## Interview Script Template

### Opening (5 min)
- Purpose of interview
- How information will be used
- Permission to record/take notes

### Context Questions (10 min)
1. Describe your current workflow for [task].
2. What are the biggest pain points?
3. What does a "good day" look like? A "bad day"?

### Requirement-Focused Questions (20 min)
4. If this system worked perfectly, what would it do?
5. What decisions do you make that this system should support?
6. What data do you currently use to make those decisions?
7. How quickly do you need a result? (latency requirement)
8. What would make you NOT trust the system's output?

### ML-Specific Questions (10 min)
9. How do you handle edge cases today?
10. What errors are acceptable? Which are catastrophic?
11. Is it worse to have a false positive or false negative?
12. How would you explain a correct decision to a customer?

### Closing (5 min)
13. What did I not ask that I should have?
14. Who else should I talk to?
```

#### Observation (Contextual Inquiry)

Best for: discovering unstated workflows, identifying real (not reported) behavior.

```markdown
## Observation Checklist

- [ ] Watch the actual workflow, not the documented one
- [ ] Note workarounds and manual steps
- [ ] Record decision points: what information is used?
- [ ] Time each step (baseline for latency requirements)
- [ ] Identify data sources actually consulted
- [ ] Ask "why" when you see something unexpected
- [ ] Document exceptions and edge cases observed
- [ ] Count frequency of different task types
```

#### Prototyping (Low-Fidelity)

Best for: validating assumptions early, surfacing UI/UX requirements, making abstract
ML concepts concrete.

```markdown
## Prototype Levels

Level 0 - Paper Sketch
- Hand-drawn interface showing model output placement
- Cost: 30 minutes
- Validates: information layout, output format

Level 1 - Spreadsheet Mockup
- Excel/Sheets with sample predictions + confidence scores
- Cost: 2-4 hours
- Validates: output granularity, threshold sensitivity

Level 2 - Interactive Mockup (Streamlit/Gradio)
- Working UI with hardcoded or rule-based predictions
- Cost: 1-2 days
- Validates: end-to-end user journey, error handling UX

Level 3 - Baseline Model Prototype
- Actual model (logistic regression / rules) in simple UI
- Cost: 3-5 days
- Validates: feasibility, data quality, performance floor
```

#### Document Analysis

Best for: extracting domain rules, compliance constraints, data dictionaries, existing SLAs.

```markdown
## Documents to Request

- [ ] Current process documentation / SOPs
- [ ] Existing data dictionaries and schemas
- [ ] Regulatory requirements (GDPR, HIPAA, SOX, etc.)
- [ ] Current SLAs and performance benchmarks
- [ ] Historical incident reports (what went wrong before)
- [ ] Audit logs (what decisions are tracked today)
- [ ] Domain glossary (terminology alignment)
- [ ] Competitor analysis / market research
```

---

### 3. Four Requirement Levels

Every ML project needs requirements at four distinct levels. Missing any level creates
gaps that surface during deployment -- the worst possible time.

#### Business Requirements

What the organization needs to achieve.

```markdown
## Business Requirements Template

### BR-001: [Title]
**Objective:** [What business outcome this enables]
**Stakeholder:** [Who benefits]
**Success Metric:** [Quantitative business KPI]
**Baseline:** [Current state of the metric]
**Target:** [Desired state with timeline]
**Constraints:** [Budget, timeline, regulatory]

### Example:
### BR-001: Reduce Customer Churn
**Objective:** Reduce monthly customer churn rate to increase LTV
**Stakeholder:** VP Revenue
**Success Metric:** Monthly churn rate
**Baseline:** 5.2% monthly churn (Q4 2025)
**Target:** <3.5% monthly churn within 6 months of deployment
**Constraints:** Budget cap $150K, GDPR compliant, no PII in model features
```

#### User Requirements

What the user needs to do with the system.

```markdown
## User Story Format

As a [role],
I want [feature/capability],
So that [benefit/value].

### Example Stories:

US-001: As a customer success manager,
        I want to see a prioritized list of at-risk customers each morning,
        so that I can proactively reach out before they churn.

US-002: As a customer success manager,
        I want to understand why a customer is flagged as at-risk,
        so that I can tailor my outreach to their specific concerns.

US-003: As a team lead,
        I want to track intervention outcomes against predictions,
        so that I can measure the model's real-world impact.
```

#### System Requirements

What the system must do technically.

```markdown
## System Requirements Template

### SR-001: [Title]
**Category:** [Functional | Performance | Security | Integration]
**Priority:** [Must | Should | Could | Won't]
**Description:** [What the system must do]
**Acceptance Criteria:** [Testable conditions]

### Example:
### SR-001: Churn Prediction API
**Category:** Functional
**Priority:** Must
**Description:** System shall expose a REST API that accepts a customer_id
and returns a churn probability score (0.0-1.0) with top-3 contributing factors.
**Acceptance Criteria:**
  - Given a valid customer_id, when the API is called, then it returns
    a JSON response with score and factors within 200ms (p95).
  - Given an invalid customer_id, when the API is called, then it returns
    a 404 with an error message.
  - Given the service is under load (100 RPS), when requests are made,
    then p99 latency remains under 500ms.
```

#### ML-Specific Requirements

What the model must achieve -- the unique layer that standard software lacks.

```markdown
## ML Requirements Template

### MLR-001: [Title]
**Type:** [Accuracy | Fairness | Robustness | Interpretability | Data]
**Description:** [What the model must achieve]
**Metric:** [Specific metric name]
**Threshold:** [Minimum acceptable value]
**Evaluation Method:** [How to measure]
**Monitoring:** [How to track in production]

### Examples:

### MLR-001: Prediction Accuracy
**Type:** Accuracy
**Description:** Model shall predict customer churn with high precision
to avoid alert fatigue for CS managers.
**Metric:** Precision at recall >= 0.70
**Threshold:** Precision >= 0.75 (i.e., at least 3 out of 4 alerts are true churners)
**Evaluation Method:** Monthly holdout evaluation on last 30 days of data
**Monitoring:** Weekly precision/recall tracking with drift alert at >5% degradation

### MLR-002: Demographic Fairness
**Type:** Fairness
**Description:** Model predictions shall not discriminate based on
customer geography or account age.
**Metric:** Equalized odds difference across geographic segments
**Threshold:** |TPR_group_A - TPR_group_B| < 0.05 for all segment pairs
**Evaluation Method:** Stratified evaluation per segment quarterly
**Monitoring:** Fairness dashboard with automatic alerting

### MLR-003: Interpretability
**Type:** Interpretability
**Description:** Each prediction must include human-readable explanations.
**Metric:** Top-3 SHAP feature attributions per prediction
**Threshold:** Explanations must cover >= 60% of prediction magnitude
**Evaluation Method:** Manual review of 50 random explanations per quarter
**Monitoring:** Explanation coverage tracked per prediction
```

---

### 4. ML Problem Statement Template

The single most important artifact in C1 Discovery. If this is wrong, everything downstream is wasted.

```markdown
## ML Problem Statement

### Project: [Name]
### Version: [X.Y]
### Date: [YYYY-MM-DD]
### Author: [Name]
### Approved by: [Name, Date]

---

### 1. Business Context
[2-3 sentences: why this matters to the organization]

### 2. Problem Framing
**Task Type:** [Classification | Regression | Ranking | Recommendation | Generation | Other]
**Input:** [Exact description of available data at inference time]
**Output:** [Exact description of what the model produces]
**Granularity:** [Per-customer? Per-transaction? Per-session?]
**Frequency:** [Real-time? Batch daily? On-demand?]

### 3. Success Criteria
| Metric           | Baseline (current) | Target (minimum) | Stretch Goal |
|-------------------|---------------------|-------------------|--------------|
| [Primary metric]  | [value]             | [value]           | [value]      |
| [Secondary metric] | [value]            | [value]           | [value]      |
| [Business metric]  | [value]            | [value]           | [value]      |

### 4. Constraints
| Constraint         | Value              | Rationale                        |
|---------------------|--------------------|----------------------------------|
| Latency (p95)      | [e.g., <200ms]     | [User-facing real-time]          |
| Fairness           | [e.g., EO diff <5%] | [Regulatory / ethical]           |
| Interpretability   | [e.g., top-3 SHAP]  | [User trust / compliance]        |
| Data freshness     | [e.g., <24h old]    | [Business relevance]             |
| Model size         | [e.g., <500MB]      | [Deployment target constraints]  |
| Cost per prediction | [e.g., <$0.001]    | [Unit economics]                 |

### 5. Data Availability
| Dataset            | Records  | Features | Quality    | Access       |
|---------------------|----------|----------|------------|--------------|
| [Dataset name]      | [count]  | [count]  | [H/M/L]   | [available/blocked] |

### 6. Risks and Assumptions
**Assumptions:**
- [List each assumption that, if wrong, invalidates the approach]

**Risks:**
| Risk                  | Probability | Impact | Mitigation                    |
|------------------------|-------------|--------|-------------------------------|
| [Data quality issues]  | [H/M/L]    | [H/M/L]| [Mitigation strategy]         |

### 7. Out of Scope
- [Explicitly list what this project will NOT do]

### 8. Definition of Done
- [ ] Model meets all threshold metrics on holdout set
- [ ] API deployed and serving predictions at target latency
- [ ] Monitoring dashboard live with alerting configured
- [ ] Documentation complete (model card, API docs, runbook)
- [ ] Stakeholder sign-off obtained
```

---

### 5. Acceptance Criteria: Given-When-Then

Every requirement must have testable acceptance criteria. Use Gherkin-style format for clarity.

```gherkin
# Functional Acceptance Criteria

Feature: Churn Prediction API

  Scenario: Successful prediction for active customer
    Given a customer with id "C-12345" exists in the database
    And the customer has at least 30 days of activity history
    When the prediction endpoint is called with customer_id "C-12345"
    Then the response status code is 200
    And the response contains a "churn_probability" between 0.0 and 1.0
    And the response contains "top_factors" with exactly 3 items
    And the response time is less than 200 milliseconds

  Scenario: Customer with insufficient history
    Given a customer with id "C-99999" has less than 30 days of history
    When the prediction endpoint is called with customer_id "C-99999"
    Then the response status code is 200
    And the response contains "churn_probability" as null
    And the response contains "reason" as "insufficient_history"

  Scenario: Non-existent customer
    Given no customer exists with id "C-00000"
    When the prediction endpoint is called with customer_id "C-00000"
    Then the response status code is 404
    And the response contains "error" as "customer_not_found"
```

```gherkin
# ML-Specific Acceptance Criteria

Feature: Model Performance

  Scenario: Accuracy on holdout set
    Given the model is evaluated on the March 2026 holdout set
    When precision is computed at recall >= 0.70
    Then precision must be >= 0.75

  Scenario: Fairness across segments
    Given the model is evaluated per geographic segment
    When equalized odds difference is computed for all segment pairs
    Then no pair has |TPR difference| > 0.05

  Scenario: Prediction latency under load
    Given the API is receiving 100 requests per second
    When latency is measured over a 10-minute window
    Then p95 latency is < 200ms
    And p99 latency is < 500ms
```

---

### 6. Definition of Done for ML Projects

Standard software DoD is necessary but not sufficient for ML. Add ML-specific checkpoints.

```markdown
## Definition of Done -- ML Project

### Code & Infrastructure
- [ ] Code reviewed and merged to main
- [ ] Unit tests pass (coverage >= 80%)
- [ ] Integration tests pass
- [ ] CI/CD pipeline green
- [ ] Infrastructure provisioned and documented

### Data
- [ ] Training data documented (source, size, date range, known biases)
- [ ] Data pipeline tested and reproducible
- [ ] Data validation checks in place (Great Expectations or equivalent)
- [ ] Data versioning configured (DVC or equivalent)

### Model
- [ ] Model meets all MLR threshold metrics on holdout set
- [ ] Model card completed (architecture, training data, limitations, biases)
- [ ] Model versioned and reproducible (MLflow or equivalent)
- [ ] A/B test plan defined (if applicable)
- [ ] Rollback procedure documented and tested

### Deployment
- [ ] API deployed and serving at target latency
- [ ] Load testing completed (meets SLA under expected traffic)
- [ ] Health check endpoint operational
- [ ] Autoscaling configured (if applicable)

### Monitoring & Operations
- [ ] Monitoring dashboard live
- [ ] Alerts configured for: latency, error rate, prediction drift, data drift
- [ ] Runbook written for common failure modes
- [ ] On-call rotation defined

### Stakeholder
- [ ] Stakeholder demo completed
- [ ] Sign-off obtained from product owner
- [ ] User documentation / training materials delivered
```

---

### 7. Requirements Traceability

Every requirement must trace forward to tests and backward to stakeholder needs.
Without traceability, you cannot prove the system does what was asked.

```markdown
## Traceability Matrix

| Req ID  | Requirement             | Source        | Test ID(s)    | Status      |
|---------|--------------------------|---------------|---------------|-------------|
| BR-001  | Reduce churn <3.5%       | VP Revenue    | AT-001        | Verified    |
| US-001  | Daily at-risk list       | CS Manager    | FT-001, FT-002| Implemented |
| US-002  | Explain risk factors     | CS Manager    | FT-003        | Implemented |
| SR-001  | Prediction API <200ms    | Architect     | PT-001, LT-001| Verified    |
| MLR-001 | Precision >=0.75 @R>=0.70| Data Science  | MT-001        | Verified    |
| MLR-002 | Fairness EO diff <0.05   | Legal         | MT-002        | Pending     |
| MLR-003 | Top-3 SHAP explanations  | CS Manager    | MT-003, FT-003| Verified    |

Legend:
- BR = Business Requirement
- US = User Story
- SR = System Requirement
- MLR = ML Requirement
- AT = Acceptance Test
- FT = Functional Test
- PT = Performance Test
- LT = Load Test
- MT = Model Test
```

#### Linking Requirements to Tests in Code

```python
import pytest

# Trace test to requirement via marker
@pytest.mark.requirement("SR-001")
@pytest.mark.requirement("MLR-001")
def test_prediction_api_returns_valid_score(client):
    """
    Traces to: SR-001 (Prediction API), MLR-001 (Accuracy)
    Validates: API returns valid churn probability.
    """
    response = client.get("/predict/C-12345")
    assert response.status_code == 200
    data = response.json()
    assert 0.0 <= data["churn_probability"] <= 1.0
    assert len(data["top_factors"]) == 3


@pytest.mark.requirement("SR-001")
def test_prediction_latency_p95(client, benchmark):
    """
    Traces to: SR-001 (Latency SLA)
    Validates: p95 latency < 200ms under normal load.
    """
    result = benchmark.pedantic(
        client.get, args=("/predict/C-12345",),
        iterations=100, rounds=5
    )
    # Verify p95 from benchmark stats
    assert benchmark.stats["ops"] > 0
```

---

### 8. Prioritization Methods

#### MoSCoW Method

Use for initial requirement triage. Forces hard conversations about what is truly mandatory.

```markdown
## MoSCoW Classification

### Must Have (non-negotiable for launch)
- MLR-001: Precision >= 0.75 at recall >= 0.70
- SR-001: Prediction API with <200ms p95 latency
- US-001: Daily at-risk customer list
- MLR-002: Fairness constraints (regulatory requirement)

### Should Have (important but launch possible without)
- US-002: Explanation of risk factors per customer
- MLR-003: SHAP-based interpretability
- SR-003: Batch prediction mode for historical analysis

### Could Have (desirable if time permits)
- US-004: Customizable risk threshold per CS manager
- SR-004: Real-time websocket notifications for high-risk events
- MLR-004: Confidence intervals on predictions

### Won't Have (this release, explicitly deferred)
- US-005: Natural language explanation generation (GPT-based)
- SR-005: Multi-language support
- MLR-005: Causal inference for intervention recommendation
```

#### RICE Scoring

Use for backlog prioritization when you need quantitative ranking.

```markdown
## RICE Scoring Framework

Score = (Reach x Impact x Confidence) / Effort

| Item                | Reach | Impact | Confidence | Effort | RICE  | Priority |
|-------------------   |-------|--------|------------|--------|-------|----------|
| Churn prediction API | 500   | 3      | 0.8        | 8      | 150.0 | 1        |
| Risk explanations    | 500   | 2      | 0.6        | 5      | 120.0 | 2        |
| Batch predictions    | 50    | 2      | 0.9        | 3      | 30.0  | 3        |
| Real-time alerts     | 200   | 1      | 0.5        | 8      | 12.5  | 4        |
| Custom thresholds    | 100   | 1      | 0.7        | 4      | 17.5  | 5        |

### Scoring Guide
- Reach: number of users/customers affected per quarter
- Impact: 3 = massive, 2 = high, 1 = medium, 0.5 = low, 0.25 = minimal
- Confidence: 1.0 = high, 0.8 = medium, 0.5 = low (penalizes uncertainty)
- Effort: person-weeks of work
```

---

## Decision Guide

```
START: New ML project requirement
  |
  v
[Have you identified all stakeholders?]
  |-- No --> Stakeholder mapping (power/interest grid)
  |-- Yes
  v
[Have you used >= 3 elicitation techniques?]
  |-- No --> Pick from: interviews, observation, prototyping, document analysis
  |-- Yes
  v
[Do you have requirements at all 4 levels?]
  |-- No --> Which level is missing?
  |          |-- Business --> Write BR docs with success metrics
  |          |-- User --> Write user stories with acceptance criteria
  |          |-- System --> Write SR docs with performance criteria
  |          |-- ML --> Write MLR docs with metrics and thresholds
  |-- Yes
  v
[Is the ML Problem Statement complete?]
  |-- No --> Fill in all 8 sections of the template
  |-- Yes
  v
[Does every requirement have acceptance criteria?]
  |-- No --> Write Given-When-Then for each requirement
  |-- Yes
  v
[Is the traceability matrix complete?]
  |-- No --> Link every requirement to at least one test
  |-- Yes
  v
[Have requirements been prioritized?]
  |-- No --> MoSCoW for initial triage, RICE for backlog ranking
  |-- Yes
  v
[Has the stakeholder approved?]
  |-- No --> Schedule review meeting, iterate
  |-- Yes
  v
DONE: Requirements approved, proceed to C2 Data
```

---

## Anti-Patterns

### 1. Vague Requirements

```markdown
BAD:  "The model should be accurate."
GOOD: "The model shall achieve precision >= 0.75 at recall >= 0.70 on the monthly
       holdout set, measured using the March 2026 evaluation pipeline."

BAD:  "The system should be fast."
GOOD: "The prediction API shall respond within 200ms (p95) under 100 RPS load."

BAD:  "The model should be fair."
GOOD: "Equalized odds difference across geographic segments shall not exceed 0.05
       for any pair of segments."
```

**Why it matters:** Vague requirements cannot be tested, cannot be verified, and create
scope creep because everyone interprets them differently.

### 2. Gold Plating

```markdown
BAD:  Adding real-time model retraining when batch daily is sufficient.
BAD:  Building a custom annotation platform when Label Studio exists.
BAD:  Implementing 15 fairness metrics when the regulation requires 2.

GOOD: Implement the minimum viable set of requirements that satisfies
      the business need, then iterate based on feedback.
```

**Why it matters:** Gold plating delays delivery, increases maintenance burden, and often
addresses problems nobody actually has. Ship the Must Haves, measure, iterate.

### 3. Missing Non-Functional Requirements (NFRs)

```markdown
Common NFRs forgotten in ML projects:

- Latency SLA (not just "fast" -- actual p95/p99 targets)
- Data freshness (how stale can training/inference data be?)
- Model staleness (when must the model be retrained?)
- Prediction volume (peak RPS, daily prediction count)
- Storage limits (model size, feature store size, log retention)
- Disaster recovery (RTO/RPO for the ML system)
- Security (who can access predictions? audit trail?)
- Cost (cost per prediction, monthly infrastructure budget)
```

**Why it matters:** NFRs drive architecture decisions. Missing them means your architecture
is designed for an unconstrained problem -- which does not exist in production.

### 4. Assumption Masquerading as Requirement

```markdown
BAD:  "The model will use XGBoost." (This is an implementation decision, not a requirement)
BAD:  "Features will be stored in Redis." (This is an architecture choice, not a requirement)
BAD:  "We will use 2 years of historical data." (This is an assumption about data availability)

GOOD: "The model shall achieve the target metrics regardless of algorithm choice."
GOOD: "Feature retrieval latency shall be < 10ms at p99."
GOOD: "Training data shall cover at least 12 months of customer behavior."
```

**Why it matters:** Encoding implementation decisions as requirements constrains the solution
space unnecessarily and prevents the team from finding better approaches.

### 5. Requirements Without Exit Criteria

```markdown
BAD:  "Explore different model architectures."
      (When is this done? After trying 2? 20? 200?)

GOOD: "Evaluate at least 3 model families (linear, tree-based, neural).
       Time-box to 2 sprints. Select the model that maximizes precision
       at recall >= 0.70 on the validation set."
```

**Why it matters:** ML experimentation without exit criteria is unbounded research, not
engineering. Every experiment must have a stopping condition.

### 6. Ignoring Data Requirements

```markdown
BAD:  Specifying model performance without specifying data quality.

GOOD:
### Data Requirements
- Training data: minimum 50K labeled examples
- Label quality: inter-annotator agreement (Cohen's kappa) >= 0.80
- Feature completeness: no feature may have > 5% missing values
- Data freshness: training data must include last 90 days
- Label latency: ground truth available within 30 days of prediction
```

**Why it matters:** Model performance is bounded by data quality. If you do not specify
data requirements, you cannot diagnose whether poor performance is a model problem or
a data problem.

---

## Templates Summary

| Artifact                | Template Section | When to Use                  |
|--------------------------|------------------|------------------------------|
| Stakeholder Register     | Section 1        | Project kickoff              |
| Interview Script         | Section 2        | Elicitation phase            |
| Business Requirements    | Section 3        | After stakeholder mapping    |
| User Stories             | Section 3        | After business requirements  |
| System Requirements      | Section 3        | After user stories           |
| ML Requirements          | Section 3        | After system requirements    |
| ML Problem Statement     | Section 4        | Central artifact of C1       |
| Acceptance Criteria      | Section 5        | Per requirement              |
| Definition of Done       | Section 6        | Project-wide, agreed at C1   |
| Traceability Matrix      | Section 7        | Maintained throughout        |
| MoSCoW Classification    | Section 8        | Initial triage               |
| RICE Scoring             | Section 8        | Backlog prioritization       |

---

## Checklist: C1 Discovery Phase Completion

```markdown
## C1 Exit Checklist

### Stakeholder Management
- [ ] Stakeholder register complete (all identified)
- [ ] Power/interest grid mapped
- [ ] Communication plan defined

### Elicitation
- [ ] At least 3 elicitation techniques used
- [ ] All key stakeholders interviewed
- [ ] Domain documents analyzed
- [ ] Prototype reviewed with end users (if applicable)

### Requirements Documentation
- [ ] Business requirements documented with success metrics
- [ ] User stories written with acceptance criteria
- [ ] System requirements specified with performance criteria
- [ ] ML requirements defined with metrics, thresholds, and evaluation methods
- [ ] ML Problem Statement complete (all 8 sections)
- [ ] Non-functional requirements explicitly documented

### Validation
- [ ] Requirements reviewed with stakeholders
- [ ] No vague or untestable requirements remain
- [ ] No implementation decisions encoded as requirements
- [ ] All assumptions explicitly documented
- [ ] Traceability matrix links every requirement to a test

### Prioritization
- [ ] MoSCoW classification complete
- [ ] RICE scoring for backlog items
- [ ] "Won't Have" items explicitly documented

### Approval
- [ ] Product owner sign-off
- [ ] Technical lead sign-off
- [ ] ⟦ user_name ⟧ approves (ARCA gate)
```
