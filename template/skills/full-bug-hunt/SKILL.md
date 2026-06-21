---
name: full-bug-hunt
description: Comprehensive multi-pass bug hunting across all layers. Deploys parallel hunters for logic, security, data, concurrency, edge cases, and integration bugs. Use when auditing any codebase before deploy.
context: fork
agent: Explore
---

# Full Bug Hunt

Multi-pass adversarial bug hunting. Each pass targets a different bug class.

## Iron Law
One pass catches 60% of bugs. Two passes catch 85%. Three passes catch 95%.
Never stop at one pass.

## Hunt Protocol (execute in order)

### Pass 1 — Static Analysis (automated)
```bash
ruff check --select E,F,W,B,SIM,UP src/
mypy src/ --strict 2>&1 | tail -30
bandit -r src/ -ll 2>&1 | tail -20
```
Report: file:line:issue for every finding.

### Pass 2 — Logic Bugs (manual review)
For each function:
- What happens with None input?
- What happens with empty collection?
- What happens with 0, negative, MAX_INT?
- What happens if called twice?
- Off-by-one in loops/slices?
- Wrong operator (> vs >=, and vs or)?
- Short-circuit evaluation traps?

### Pass 3 — Security Bugs
- SQL injection: f-strings in queries?
- Path traversal: user input in file paths?
- Secrets: hardcoded tokens/passwords?
- Deserialization: pickle/yaml.load without SafeLoader?
- SSRF: user-controlled URLs without validation?
- Auth bypass: missing permission checks?
```bash
rg -i 'password|secret|token|api.key' src/ --count
rg 'execute\s*\(\s*f["\047]' src/
rg 'pickle\.load|yaml\.load' src/
```

### Pass 4 — Data & State Bugs
- Race conditions: shared mutable state without locks?
- Data leakage: train data info in test pipeline?
- Schema drift: assumed columns that might not exist?
- Encoding: UTF-8 assumptions on user input?
- Timezone: naive datetime where aware is needed?

### Pass 5 — Edge Cases & Error Handling
- Bare except or except Exception?
- None returned as error signal?
- Resources not closed (files, connections, cursors)?
- Retry without backoff?
- Timeout missing on network calls?

### Pass 6 — Integration Bugs
- API contract mismatches between modules?
- Import cycles?
- Environment assumptions (paths, env vars, ports)?
- Docker: works locally, fails in container?

## Output Format
╔══════════════════════════════════════╗
║  FULL BUG HUNT — [project/module]    ║
╠══════════════════════════════════════╣
PASS 1 (Static): [N] findings
PASS 2 (Logic):  [N] findings
PASS 3 (Security): [N] findings
PASS 4 (Data/State): [N] findings
PASS 5 (Edge Cases): [N] findings
PASS 6 (Integration): [N] findings
CRITICAL: [list with file:line]
HIGH:     [list with file:line]
MEDIUM:   [list with file:line]
TOTAL: [N] bugs found in [N] passes
╚══════════════════════════════════════╝

<!-- ultrathink: extended thinking activo en esta skill/agent -->
