#!/usr/bin/env bash
# ARCA — adr-namespace-validator (PostToolUse:Edit + PostToolUse:Write)
#
# Implements ADR-044 (ADR namespace convention).
#
# Fires when an edited file mentions a bare `ADR-NNN` reference. For each
# match, checks whether the number exists in 2+ ADR namespaces (root
# docs/adr/ + any subdirectory matching `*/docs/adr/`). If ambiguous AND
# the file is NOT itself inside an ADR namespace directory (where the
# scope is implicit), emits a stderr advisory citing both candidates.
#
# Advisory-only. Exit 0 always. Does NOT block writes.
#
# Skipped silently when:
#   - The modified file is inside any `*/docs/adr/` tree (implicit scope).
#   - jq is missing (cannot parse hook input).
#   - The project basename is in the meta-ecosystem denylist (ADR-037),
#     EXCEPT .claude (its docs/adr/ IS the canonical root).
#   - ARCA_ADR_NAMESPACE_DISABLE=1 is set.

set -uo pipefail

payload="$(cat -)"

if ! command -v jq >/dev/null 2>&1; then
    exit 0
fi

file_path="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty' 2>/dev/null || echo "")"
cwd="$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null || echo "$PWD")"

# Bypass.
if [[ "${ARCA_ADR_NAMESPACE_DISABLE:-0}" == "1" ]]; then
    stats_file="${HOME}/.claude/state/adr-namespace-stats.json"
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
            jq -n '{advisory_emitted:0, bypass:1, last_bypass_at: now}' >"$stats_file"
        fi
    ) 9>"${stats_file}.lock"
    exit 0
fi

# File must exist + be readable.
if [[ -z "$file_path" ]] || [[ ! -f "$file_path" ]]; then
    exit 0
fi

# Skip files inside any */docs/adr/ tree — the scope is implicit there.
case "$file_path" in
    */docs/adr/*) exit 0 ;;
esac

# Denylist meta-ecosystem repos (composes with ADR-037), but allow
# .claude itself (its docs/adr/ IS the canonical root).
denylist_file="${HOME}/.claude/hooks/lib/phase-state-denylist.txt"
project_basename="$(basename "${cwd:-$PWD}")"
if [[ -f "$denylist_file" ]] && [[ "$project_basename" != ".claude" ]] \
   && grep -qE "^${project_basename}$" "$denylist_file" 2>/dev/null; then
    exit 0
fi

# Locate the repo root by walking up from the file path until a `docs/adr/`
# directory is found. This anchors the ADR namespace discovery.
abs_path="$file_path"
if [[ "$abs_path" != /* ]]; then
    abs_path="${cwd:-$PWD}/$abs_path"
fi
dir="$(cd "$(dirname "$abs_path")" 2>/dev/null && pwd || echo "")"
repo_root=""
while [[ -n "$dir" && "$dir" != "/" ]]; do
    if [[ -d "$dir/docs/adr" ]]; then
        repo_root="$dir"
        break
    fi
    dir="$(dirname "$dir")"
done

if [[ -z "$repo_root" ]]; then
    exit 0
fi

# Extract bare "ADR-NNN" mentions from the file. Anchor on word boundary
# to avoid matching things like "ADR-NNN-extra-words" (those are filenames
# inside namespaces). Use a fixed-width 3-digit pattern matching the
# project convention.
#
# Note: grep -o gives one match per line; sort -u dedupes.
mentions="$(grep -oE 'ADR-[0-9]{3}' "$file_path" 2>/dev/null | sort -u || true)"
[[ -z "$mentions" ]] && exit 0

# Discover all ADR namespaces under repo_root: root docs/adr/ + any
# */docs/adr/ subdirectory (max depth 3 to keep the scan cheap).
declare -a namespaces=("docs/adr")
while IFS= read -r ns; do
    [[ -z "$ns" ]] && continue
    rel="${ns#$repo_root/}"
    [[ "$rel" == "docs/adr" ]] && continue
    namespaces+=("$rel")
done < <(find "$repo_root" -maxdepth 4 -type d -path '*/docs/adr' 2>/dev/null)

# For each mentioned ADR-NNN, check how many namespaces have a file
# matching that ID. The two prefix patterns: NNN-* (root style) and
# ADR-NNN-* (sub-project style).
ambiguous=()
for m in $mentions; do
    nnn="${m#ADR-}"
    hits=()
    for ns in "${namespaces[@]}"; do
        # Look for both prefix styles in each namespace.
        for prefix_pattern in "${nnn}-" "ADR-${nnn}-"; do
            for f in "$repo_root/$ns/${prefix_pattern}"*.md; do
                [[ -f "$f" ]] || continue
                hits+=("${f#$repo_root/}")
            done
        done
    done
    if [[ "${#hits[@]}" -ge 2 ]]; then
        # Format: "ADR-NNN|path1|path2|..."
        joined="$m"
        for h in "${hits[@]}"; do
            joined="${joined}|${h}"
        done
        ambiguous+=("$joined")
    fi
done

if [[ "${#ambiguous[@]}" -eq 0 ]]; then
    exit 0
fi

# Emit advisory.
{
    printf '\n[ADR-NAMESPACE WARN] %s mentions ADR ID(s) that exist in multiple namespaces:\n' "$file_path"
    for a in "${ambiguous[@]}"; do
        # Parse "ADR-NNN|path1|path2|..."
        IFS='|' read -ra parts <<<"$a"
        adr_id="${parts[0]}"
        printf '  %s:\n' "$adr_id"
        for ((i=1; i<${#parts[@]}; i++)); do
            printf '    - %s\n' "${parts[$i]}"
        done
    done
    printf '  Disambiguate with path-prefix per ADR-044 §2: "root ADR-NNN" or "<subdir> ADR-NNN".\n'
    printf '  Bypass: ARCA_ADR_NAMESPACE_DISABLE=1\n'
} >&2

# Persist stats. P0-H2 fix (audit 2026-05-16): atomic via flock.
stats_file="${HOME}/.claude/state/adr-namespace-stats.json"
mkdir -p "$(dirname "$stats_file")"
(
    flock -w 5 9 || exit 1
    if [[ -f "$stats_file" ]]; then
        tmp="${stats_file}.tmp.$$"
        jq --arg p "$file_path" \
           '.advisory_emitted = (.advisory_emitted // 0) + 1
            | .last_advisory_path = $p
            | .last_advisory_at = now' \
            "$stats_file" >"$tmp" 2>/dev/null \
            && mv "$tmp" "$stats_file" \
            || rm -f "$tmp"
    else
        jq -n --arg p "$file_path" \
            '{advisory_emitted:1, bypass:0,
              last_advisory_path:$p, last_advisory_at: now}' >"$stats_file"
    fi
) 9>"${stats_file}.lock"

# Advisory only — exit 0.
exit 0
