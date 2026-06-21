---
description: On-demand intelligence fetch for a target — CVEs, disclosed reports, new features. Delegates to @cve-hunter + hunt memory context. Usage: /intel target.com
---

# /intel

Fetch actionable intelligence for a target.

## What This Does

1. Delegates to `@cve-hunter` to match CVEs and security advisories (NVD + GitHub Advisory) against the target's known tech stack
2. Fetches HackerOne Hacktivity for the target (via HackerOne MCP if available)
3. Cross-references with hunt memory — flags untested CVEs and new endpoints
4. Outputs prioritized intel with hunt recommendations

## Usage

```
/intel target.com
```

## Output

```
INTEL: target.com
═══════════════════════════════════════

ALERTS:
[CRITICAL] CVE-2026-XXXX — Next.js middleware bypass (CVSS 9.1)
  target.com runs Next.js 14.2.3 (vulnerable). Patch: 14.2.4.
  → You haven't tested this endpoint yet. Hunt candidate.

[HIGH] New feature detected: /api/v3/billing/invoices
  Not in your tested_endpoints list. 3 new paths.
  → New = unreviewed. Priority hunt target.

[INFO] 2 new disclosed reports on HackerOne for target.com
  → Read for methodology insights before hunting.

MEMORY CONTEXT:
  Last hunted: 2026-03-24 (2 days ago)
  Tech stack: Next.js 14.2.3, GraphQL, PostgreSQL
  Untested CVEs: 1 critical, 0 high
```

## Data Sources

| Source | What | Auth required? |
|---|---|---|
| NVD (via `@cve-hunter`) | CVEs matching tech stack | No |
| GitHub Advisory (via `@cve-hunter`) | Security advisories | No |
| HackerOne Hacktivity | Disclosed reports | No |
| HackerOne MCP (if connected) | Program stats, policy | No (public) |
| Hunt memory | Previously tested endpoints | Local files |
