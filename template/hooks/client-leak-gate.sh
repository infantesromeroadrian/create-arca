#!/bin/bash
# PreToolUse hook (Bash) — Client-Facing Internal-Jargon Leak Gate.
#
# WHY (incident 2026-06-01): an ADR and a test docstring carrying ARCA-internal
# agent names (`@architect-ai`, `@code-critic`, `@math-critic`, `@monitoring`)
# plus internal tooling references were committed into a CLIENT repo
# (⟦ org_name ⟧) and only caught by a manual audit. The orchestrator is supposed to
# catch this before it ships; this hook makes it non-negotiable.
#
# WHAT: when a `git commit` (or `git push`) is about to land on a repo whose
# `origin` remote points at a known CLIENT host, scan the STAGED diff (added
# lines only) for ARCA-internal terminology and BLOCK (exit 2) if any is found.
#
# SCOPE / SAFETY:
#   * Only fires on `git commit` / `git push` commands.
#   * Only fires when origin remote matches a CLIENT host (see CLIENT_HOSTS).
#     Internal artifacts (Obsidian vault, .claude, personal projects,
#     GitHub personal mirrors) are therefore exempt automatically.
#   * Fail-OPEN: if the repo dir / remote / diff cannot be determined, the hook
#     exits 0 (allows). It only blocks when it is SURE it is a client repo AND
#     there is a real jargon hit. This trades a possible false-negative for zero
#     false-positives on unrelated projects — the orchestrator remains the backup.
#   * Self-test: run `client-leak-gate.sh --self-test` to validate patterns and
#     client-host detection without touching any repo.
#
# Registered as a PreToolUse hook with a Bash matcher in settings.json.

set -euo pipefail

# ---------------------------------------------------------------------------
# Client repo hosts. EXTEND this list as new client repos appear.
# Anchored to the host portion of the remote URL.
# ---------------------------------------------------------------------------
CLIENT_HOSTS='bitbucket\.dev\.⟦ org_name ⟧\.com'

# ---------------------------------------------------------------------------
# ARCA-internal jargon patterns.
#
# Two precision tiers, learned from the code-critic review (2026-06-02):
#
# LIST_A — UNAMBIGUOUS ARCA names: they essentially never appear as plain
# industry roles/terms, so they are matched WITHOUT a leading '@' (and
# case-insensitively) to also catch prose like "code-critic GO" — exactly the
# form that leaked on 2026-06-01.
#
# LIST_B — names that ALSO exist as legitimate industry roles/tooling. A client
# repo may write "network-engineer" or "prompt-engineer" as a plain job title,
# so these are matched ONLY with a leading '@' — which is how ARCA always writes
# an agent handle. Industry prose therefore never trips them.
#
# LIST_C_CS — internal process vocabulary, matched CASE-SENSITIVELY in its exact
# ARCA spelling, so neutral phrases ("gate chain of custody", "six hats
# meeting") do not match. ARCA writes "Gate chain:", "(Six Hats)", "ARCA".
# ---------------------------------------------------------------------------
LIST_A='\b(math-critic|code-critic|debt-detector|architect-ai|ai-red-teamer|ai-redteam-orchestrator|arca-ambient-monitor|code-narrator|maintainability-engineer|compound-ai-architect|mcp-security-auditor|htb-orchestrator|htb-recon|cve-hunter|exploit-executor|flag-validator|bug-bounty-hunter)\b'

LIST_B='@(monitoring|tester|deployment|devops|ml-engineer|dl-engineer|ai-engineer|data-engineer|data-scientist|data-validator|gpu-engineer|rag-engineer|agent-engineer|mlops-engineer|python-specialist|aws-engineer|frontend-ai|git-master|docs-writer|sensei|api-designer|perf-engineer|network-engineer|prompt-engineer|cost-analyzer|formal-verifier|rl-engineer|model-evaluator|checkpoint-manager|credential-hunter|chief-architect|distributed-training-engineer|alignment-researcher|interpretability-researcher|evals-engineer|trust-and-safety-engineer|rust-systems-engineer|skill-router|token-optimizer|project-planner|ai-production-engineer)'

# Case-insensitive tier (agent names: A without '@', B with '@').
JARGON_CI="${LIST_A}|${LIST_B}"

# Case-sensitive tier ("Gate chain:" requires the trailing colon so
# "gate chain of custody" is not a hit).
LIST_C_CS='([Gg]ate chain:|Six Hats|⟦ user_title ⟧|Pipeline ART|\bARCA\b)'

# scan <text> -> exit 0 if a hit, 1 if clean. Mirrors the runtime scan exactly
# so the self-test exercises the real predicate.
scan() {
  echo "$1" | grep -qiE "$JARGON_CI" && return 0
  echo "$1" | grep -qE  "$LIST_C_CS" && return 0
  return 1
}

# ---------------------------------------------------------------------------
# Self-test mode: validate the patterns + host detection in isolation.
# ---------------------------------------------------------------------------
if [[ "${1:-}" == "--self-test" ]]; then
  fail=0
  check() { # check <should_match:0|1> <text>
    local want="$1"; shift
    if scan "$*"; then got=1; else got=0; fi
    if [[ "$got" != "$want" ]]; then echo "FAIL (want=$want got=$got): $*"; fail=1
    else echo "ok   (match=$got): $*"; fi
  }
  echo "== jargon SHOULD match =="
  check 1 "decided by @architect-ai and reviewed"
  check 1 "code-critic GO after 2 rounds"
  check 1 "@math-critic validated the ratio"
  check 1 "@monitoring lands the implementation"
  check 1 "Gate chain: code review GO"
  check 1 "Deliberación (Six Hats)"
  check 1 "⟦ user_title ⟧' instruction was explicit"
  check 1 "used elsewhere in ARCA"
  check 1 "escalated to @network-engineer for review"   # B-list WITH '@' is jargon
  check 1 "@prompt-engineer owns this prompt"
  echo "== legit prose / code SHOULD NOT match =="
  check 0 "@property"
  check 0 "@staticmethod"
  check 0 "@pytest.mark.parametrize"
  check 0 "@app.entrypoint handler"
  check 0 "the monitoring dashboard uses CloudWatch"
  check 0 "Alejandro the tester from ⟦ org_name ⟧"
  check 0 "validación estadística + code review (2 rondas)"
  check 0 "SUM(SEARCH(...)) for additive counts"
  check 0 "def _make_aggregated_metric(self, metric_name):"
  check 0 "We hired a senior network-engineer for the VLAN redesign"   # B-list w/o '@'
  check 0 "the prompt-engineer role focuses on eval harnesses"
  check 0 "cost-analyzer module v2 shipped"
  check 0 "formal-verifier library integration"
  check 0 "model-evaluator service latency"
  check 0 "gate chain of custody for evidence"
  check 0 "six hats meeting notes from Q2"
  echo "== client-host detection =="
  for u in \
    "https://your-client-git-host.example.com/scm/mkt/repo.git:1" \
    "git@github.com:⟦ github_user ⟧/client-work.git:0" \
    "https://github.com/⟦ github_user ⟧/⟦ org_name ⟧-Work.git:0"; do
    url="${u%:*}"; want="${u##*:}"
    if echo "$url" | grep -qiE "$CLIENT_HOSTS"; then got=1; else got=0; fi
    if [[ "$got" == "$want" ]]; then echo "ok   (client=$got): $url"; else echo "FAIL (want=$want got=$got): $url"; fail=1; fi
  done
  [[ "$fail" == 0 ]] && { echo "SELF-TEST PASSED"; exit 0; } || { echo "SELF-TEST FAILED"; exit 1; }
fi

# ---------------------------------------------------------------------------
# Normal PreToolUse path.
# ---------------------------------------------------------------------------
# jq parses the PreToolUse JSON; if it is missing we cannot read the command,
# so fail-open (consistent with the rest of the hook roster).
command -v jq >/dev/null 2>&1 || exit 0

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || echo "")
[[ -z "$CMD" ]] && exit 0

# Only act on git commit / git push.
echo "$CMD" | grep -qE '\bgit\b([^&|;]*)\b(commit|push)\b' || exit 0

# Best-effort repo-dir extraction from the command. This is intentionally
# best-effort: exotic forms (paths with spaces, chained `cd a && cd b`,
# subshells, `cd` text inside the commit message) degrade to fail-OPEN — they
# either resolve to a non-existent dir or to a non-client repo, never to a
# false block. The orchestrator remains the backstop for those.
REPO_DIR=""
if echo "$CMD" | grep -qE 'git +-C +'; then
  REPO_DIR=$(echo "$CMD" | sed -nE 's/.*git +-C +"?([^" &|;]+)"?.*/\1/p' | head -1)
fi
if [[ -z "$REPO_DIR" ]] && echo "$CMD" | grep -qE '(^|&&|;)[[:space:]]*cd +'; then
  REPO_DIR=$(echo "$CMD" | sed -nE 's/.*(^|&&|;)[[:space:]]*cd +"?([^"&|;]+)"?.*/\2/p' | head -1 | sed 's/[[:space:]]*$//')
fi
[[ -z "$REPO_DIR" ]] && REPO_DIR="."
[[ -d "$REPO_DIR" ]] || exit 0  # fail-open: can't resolve dir

# Origin remote → is this a CLIENT repo?
REMOTE=$(git -C "$REPO_DIR" remote get-url origin 2>/dev/null || echo "")
[[ -z "$REMOTE" ]] && exit 0                                   # not a git repo → allow
echo "$REMOTE" | grep -qiE "$CLIENT_HOSTS" || exit 0           # not a client repo → allow

# Staged (about-to-commit) diff. Fall back to unstaged if nothing staged.
DIFF=$(git -C "$REPO_DIR" diff --cached 2>/dev/null || echo "")
[[ -z "$DIFF" ]] && DIFF=$(git -C "$REPO_DIR" diff 2>/dev/null || echo "")
[[ -z "$DIFF" ]] && exit 0  # nothing to inspect → allow

# Only inspect ADDED lines (leading '+', excluding the '+++' file header).
ADDED=$(echo "$DIFF" | { grep -E '^\+' || true; } | { grep -vE '^\+\+\+' || true; })
[[ -z "$ADDED" ]] && exit 0

# Two grep tiers (CI names + CS process vocab); awk dedups lines that match
# both tiers so a single offending line is reported once.
HITS=$( { echo "$ADDED" | grep -niE "$JARGON_CI" || true; echo "$ADDED" | grep -nE "$LIST_C_CS" || true; } | awk '!seen[$0]++' | head -8 )

if [[ -n "$HITS" ]]; then
  {
    echo "BLOCKED [client-leak-gate]: ARCA-internal terminology is staged for a CLIENT repo."
    echo "  repo remote : $REMOTE"
    echo "  offending added lines:"
    echo "$HITS" | sed 's/^/    /'
    echo "  Neutralize the internal agent/tooling names (e.g. '@code-critic' -> 'code review',"
    echo "  'Gate chain:' -> 'review process:') before committing to a client repo."
  } >&2
  exit 2
fi

exit 0
