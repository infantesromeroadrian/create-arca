#!/usr/bin/env bash
# ARCA — eval-suite-coverage-detector (PostToolUse:Edit + PostToolUse:Write)
#
# Implements ADR-042 (Eval suite mandate — every agent MUST have
# evals/scenarios/<name>/scenario.json).
#
# Fires when the modified path matches `**/agents/<slug>.md`. Resolves the
# agent slug from the basename and checks for the sibling scenario file at
# `<repo>/evals/scenarios/<slug>/scenario.json`. If absent, emits an advisory
# line to stderr inviting the operator to run `/eval-skeleton <slug>`.
#
# Advisory-only. Exit 0 always. Does NOT block writes.
#
# Skipped silently when:
#   - The modified path is not under agents/ (no match).
#   - The project basename is in the meta-ecosystem denylist (ADR-037), EXCEPT
#     for .claude itself, where agents/ IS the canonical source of
#     truth and the invariant applies. (The other denylisted repos — snapshots
#     and vault-notes — do not contain agent prompts.)
#   - ARCA_EVAL_COVERAGE_DISABLE=1 is set.
#
# Stdin: JSON payload with at minimum tool_input.file_path (Edit) or
# tool_input.file_path (Write).

set -uo pipefail

# Read JSON payload from stdin.
payload="$(cat -)"

# Extract the modified file path (jq required for parse — fallback: silent).
if ! command -v jq >/dev/null 2>&1; then
    exit 0
fi

file_path="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty' 2>/dev/null || echo "")"
cwd="$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null || echo "$PWD")"

# Bypass.
if [[ "${ARCA_EVAL_COVERAGE_DISABLE:-0}" == "1" ]]; then
    stats_file="${HOME}/.claude/state/eval-coverage-stats.json"
    mkdir -p "$(dirname "$stats_file")"
    # P0-H2 fix (audit 2026-05-16): atomic stats update via flock.
    (
        flock -w 5 9 || exit 1
        if [[ -f "$stats_file" ]]; then
            tmp="${stats_file}.tmp.$$"
            jq '.bypass = (.bypass // 0) + 1 | .last_bypass_at = now' \
                "$stats_file" >"$tmp" 2>/dev/null \
                && mv "$tmp" "$stats_file" \
                || rm -f "$tmp"
        else
            jq -n '{advisory_emitted:0, bypass:1, skeleton_generated:0, last_bypass_at: now}' \
                >"$stats_file"
        fi
    ) 9>"${stats_file}.lock"
    exit 0
fi

# Path filter — only fire for files under agents/ with the .md extension.
# Matches absolute paths (.../agents/foo.md), nested-relative (./agents/foo.md)
# and bare-relative (agents/foo.md without prefix). The bare-relative branch
# is defensive — Claude Code runtime today passes absolute paths, but a
# future tool variant may pass relative without `./` prefix.
case "$file_path" in
    */agents/*.md|agents/*.md) : ;;
    *) exit 0 ;;
esac

# Reject paths that descend further than one level under agents/ (sub-dirs
# are not agent prompts in this layout; CLAUDE.md confirms agents/<name>.md
# is flat).
relative="${file_path##*/agents/}"
case "$relative" in
    */*) exit 0 ;;
esac

# Resolve agent slug (basename without .md).
slug="${relative%.md}"
if [[ -z "$slug" ]]; then
    exit 0
fi

# Denylist meta-ecosystem repos (composes with ADR-037), but allow
# .claude itself because that IS the canonical agents/ source.
denylist_file="${HOME}/.claude/hooks/lib/phase-state-denylist.txt"
project_basename="$(basename "${cwd:-$PWD}")"
if [[ -f "$denylist_file" ]] && [[ "$project_basename" != ".claude" ]] \
   && grep -qE "^${project_basename}$" "$denylist_file" 2>/dev/null; then
    exit 0
fi

# Locate the repo root containing agents/. The hook may be invoked from a
# subdirectory; walk up from the file path's parent until we find agents/.
abs_path="$file_path"
if [[ "$abs_path" != /* ]]; then
    abs_path="${cwd:-$PWD}/$abs_path"
fi
dir="$(cd "$(dirname "$abs_path")" 2>/dev/null && pwd || echo "")"
repo_root=""
while [[ -n "$dir" && "$dir" != "/" ]]; do
    if [[ -d "$dir/agents" && -d "$dir/evals" ]]; then
        repo_root="$dir"
        break
    fi
    dir="$(dirname "$dir")"
done

# If we cannot find a repo root with evals/, do not emit an advisory — we
# would be guessing.
if [[ -z "$repo_root" ]]; then
    exit 0
fi

scenario_path="${repo_root}/evals/scenarios/${slug}/scenario.json"

stats_file="${HOME}/.claude/state/eval-coverage-stats.json"
mkdir -p "$(dirname "$stats_file")"

if [[ -f "$scenario_path" ]]; then
    # Coverage present — silent. No counter bump (success path is not a stat
    # we want to inflate; only advisories are signal).
    exit 0
fi

# Emit advisory.
{
    printf '\n[EVAL-COVERAGE WARN] agents/%s.md has no evals/scenarios/%s/scenario.json\n' "$slug" "$slug"
    printf '  Run: /eval-skeleton %s   (generates a minimal template to refine)\n' "$slug"
    printf '  Spec: docs/adr/042-eval-suite-mandate.md\n'
    printf '  Bypass: ARCA_EVAL_COVERAGE_DISABLE=1\n'
} >&2

# Persist stats. P0-H2 fix (audit 2026-05-16): atomic via flock.
(
    flock -w 5 9 || exit 1
    if [[ -f "$stats_file" ]]; then
        tmp="${stats_file}.tmp.$$"
        jq --arg a "$slug" \
           '.advisory_emitted = (.advisory_emitted // 0) + 1
            | .last_advisory_agent = $a
            | .last_advisory_at = now' \
            "$stats_file" >"$tmp" 2>/dev/null \
            && mv "$tmp" "$stats_file" \
            || rm -f "$tmp"
    else
        jq -n --arg a "$slug" \
            '{advisory_emitted:1, bypass:0, skeleton_generated:0,
              last_advisory_agent:$a, last_advisory_at: now}' >"$stats_file"
    fi
) 9>"${stats_file}.lock"

# Advisory only — exit 0 (never blocks).
exit 0
