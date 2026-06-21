---
name: transilience-hackerone
description: HackerOne bug bounty automation - parses scope CSVs, deploys parallel pentesting agents per asset, validates PoCs, and generates platform-ready submission reports.
---

# HackerOne Bug Bounty

Automates: scope parsing → parallel testing per asset → PoC validation → submission reports.

## Quick start

1. Input: HackerOne program URL or scope CSV.
2. Parse scope and program guidelines.
3. Spawn one coordinator per eligible asset (parallel).
4. Each coordinator runs the standard engagement flow: recon (`transilience-reconnaissance`) → vuln class testing (`transilience-injection`, `transilience-api-security`) → PoC capture → finding write-up. See the inline coordinator scaffold below.
5. Validate PoCs, generate HackerOne-formatted reports.

## Scope CSV format

Expected columns:
- `identifier` — asset URL/domain.
- `asset_type` — URL, WILDCARD, API, CIDR.
- `eligible_for_submission` — must be `true`.
- `max_severity` — critical / high / medium / low.
- `instruction` — asset-specific notes.

Parse with `tools/csv_parser.py`. Filter for `eligible_for_submission=true`.

## Agent deployment

One coordinator per asset, spawned in parallel. The coordinator scaffold is inline (no external coordination skill): each coordinator owns one asset end-to-end — recon, vuln-class testing, PoC capture, and finding write-up — and isolates its work under a per-asset `OUTPUT_DIR`.

```python
coordinator_role = (
    "You are a per-asset bug bounty coordinator. Run the engagement flow on ONE asset:\n"
    "1. Recon (subdomains, ports, endpoints, APIs).\n"
    "2. Vuln-class testing (injection, BOLA/IDOR, auth, SSRF, etc.).\n"
    "3. Capture an executable PoC + timestamped output for every confirmed finding.\n"
    "4. Write each finding to findings/ with the standard finding contract.\n"
    "Stay strictly within the declared scope. Save all raw tool output."
)
Agent(prompt=f"{coordinator_role}\n\nTARGET: {asset_url}\nSCOPE: {program_guidelines}\nOUTPUT_DIR: ...",
      run_in_background=True)
```

10 assets → 10 parallel coordinators (~2-4 h vs 20-40 h sequential). Each coordinator follows the inline scaffold above and routes per vuln class to `transilience-reconnaissance`, `transilience-injection`, and `transilience-api-security`.

## PoC validation

Every finding requires:
1. `poc.py` — executable exploit script.
2. `poc_output.txt` — timestamped execution proof.
3. `workflow.md` — manual repro steps if applicable.
4. Evidence screenshots / HTTP captures / video.

Validate each finding against the engagement-thoroughness contract: a finding is only complete when all four artifacts above exist and the PoC reproduces against the live target. The HackerOne PoC contract is a superset of this standard finding contract — it additionally requires the submission report sections below.

## Submission report format

Required sections per HackerOne standard:
1. Summary (2-3 sentences).
2. Severity (CVSS v3.1 + business impact).
3. Steps to Reproduce (numbered, clear).
4. Visual Evidence.
5. Impact (realistic attack scenario).
6. Remediation (actionable fixes).

Validate with `tools/report_validator.py`.

## Output structure

A per-asset `OUTPUT_DIR` (one isolated tree per coordinator, never shared) plus a per-asset `reports/submissions/` containing the platform-ready markdown. Keep raw tool output, findings, and reports under separate subdirectories so artifacts never collide across assets.

```
{OUTPUT_DIR}/
├── findings/
├── reports/
│   ├── submissions/
│   │   ├── H1_CRITICAL_001.md
│   │   └── H1_HIGH_001.md
│   └── SUBMISSION_GUIDE.md
├── recon/
├── logs/
└── artifacts/
```

## Program selection

**High-value:** new programs (< 30 days), fast response (< 24 h), high bounties, large attack surface. **Avoid:** slow response (> 1 week), low bounties, restrictive scope.

## Submission checklist

- [ ] Working PoC with `poc_output.txt`.
- [ ] CVSS v3.1 score with justification.
- [ ] Step-by-step reproduction.
- [ ] Visual evidence.
- [ ] Realistic impact.
- [ ] Remediation guidance.
- [ ] Sensitive data sanitized.
- [ ] Asset is `eligible_for_submission=true`.

## Common rejections (preempt)

| Rejection | Prevention |
|-----------|------------|
| Out of Scope | Verify `eligible_for_submission=true` and asset-type match |
| Cannot Reproduce | Include `poc.py` + `poc_output.txt`; engagement-thoroughness validator catches missing artifacts |
| Duplicate | Search disclosed reports before submission; submit quickly |
| Insufficient Impact | Document realistic attack scenario in the report |

## Tools

- `tools/csv_parser.py` — parse HackerOne scope CSVs.
- `tools/report_validator.py` — validate report completeness.
- Per-vuln-class routing: `transilience-reconnaissance`, `transilience-injection`, `transilience-api-security`.

## Usage

```bash
/hackerone <program_url_or_csv_path>
```
