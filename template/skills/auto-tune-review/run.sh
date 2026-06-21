#!/usr/bin/env bash
# /auto-tune-review — HITL handoff for code-critic-rejected agents.
#
# Implements ADR-041 §3. Pure read-only consumer. Reads
# ~/.claude/state/critic_rejections.json + recent transcripts under
# ~/.claude/projects/<slug>/*.jsonl, prints structured handoff context
# the operator pastes into @prompt-engineer.

set -uo pipefail

# ----- Argument parsing -----

agent_name=""
limit=5
json_mode=0
include_resolved=0

usage() {
    cat <<'EOF'
Usage: auto-tune-review <agent-name> [--limit=N] [--json] [--include-resolved]

Reads ~/.claude/state/critic_rejections.json + recent session transcripts
and emits a structured handoff for @prompt-engineer review.

Exit codes:
  0 — success
  1 — argument error, state missing, agent not pending (without --include-resolved),
      or jq missing
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --limit=*) limit="${1#--limit=}" ;;
        --json) json_mode=1 ;;
        --include-resolved) include_resolved=1 ;;
        -h|--help) usage; exit 0 ;;
        --*) printf 'auto-tune-review: unknown flag %q\n' "$1" >&2; usage >&2; exit 1 ;;
        *)
            if [[ -z "$agent_name" ]]; then
                agent_name="$1"
            else
                printf 'auto-tune-review: unexpected positional %q\n' "$1" >&2
                exit 1
            fi
            ;;
    esac
    shift
done

if [[ -z "$agent_name" ]]; then
    printf 'auto-tune-review: <agent-name> required\n' >&2
    usage >&2
    exit 1
fi

if ! [[ "$limit" =~ ^[0-9]+$ ]] || [[ "$limit" -lt 1 ]]; then
    printf 'auto-tune-review: --limit must be positive integer (got %q)\n' "$limit" >&2
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    printf 'auto-tune-review: jq required\n' >&2
    exit 1
fi

# ----- Resolve paths -----

# REPO_ROOT preference: env override (for tests), then walk up from CWD,
# then fall back to the canonical a prior laptop path documented in CLAUDE.md.
REPO_ROOT="${ARCA_REPO_ROOT:-}"
if [[ -z "$REPO_ROOT" ]]; then
    cur="$PWD"
    while [[ "$cur" != "/" ]]; do
        if [[ -f "$cur/CLAUDE.md" && -d "$cur/agents" && -d "$cur/hooks" ]]; then
            REPO_ROOT="$cur"
            break
        fi
        cur="$(dirname "$cur")"
    done
fi
if [[ -z "$REPO_ROOT" ]]; then
    REPO_ROOT="${HOME}/projects/Projects/.claude"
fi

state_file="${HOME}/.claude/state/critic_rejections.json"
prompt_path="${REPO_ROOT}/agents/${agent_name}.md"
transcripts_dir="${HOME}/.claude/projects"
sla_days="${ARCA_AUTOTUNE_SLA_DAYS:-7}"

if [[ ! -f "$state_file" ]]; then
    printf 'auto-tune-review: state file missing at %q (tracker has not run yet)\n' "$state_file" >&2
    exit 1
fi

if [[ ! -f "$prompt_path" ]]; then
    printf 'auto-tune-review: agent prompt not found at %q\n' "$prompt_path" >&2
    exit 1
fi

# ----- Read state -----

rejections=$(jq -r --arg a "$agent_name" '.rejections[$a] // 0' "$state_file" 2>/dev/null)
pending_since=$(jq -r --arg a "$agent_name" '.pending_since[$a] // ""' "$state_file" 2>/dev/null)
is_pending=$(jq --arg a "$agent_name" \
    '[.auto_tune_pending[]? | select(. == $a)] | length' "$state_file" 2>/dev/null)

if [[ "$is_pending" -eq 0 && "$include_resolved" -eq 0 ]]; then
    printf 'auto-tune-review: @%s is not in auto_tune_pending. Use --include-resolved to inspect anyway.\n' "$agent_name" >&2
    exit 1
fi

# Days pending.
days_pending=0
if [[ -n "$pending_since" && "$pending_since" != "null" ]]; then
    if command -v python3 >/dev/null 2>&1; then
        days_pending=$(python3 - "$pending_since" <<'PYEOF' 2>/dev/null
import sys
from datetime import datetime, timezone
iso = sys.argv[1]
try:
    if iso.endswith("Z"):
        iso = iso[:-1] + "+00:00"
    t = datetime.fromisoformat(iso)
    if t.tzinfo is None:
        t = t.replace(tzinfo=timezone.utc)
    delta = datetime.now(timezone.utc) - t
    print(int(delta.total_seconds() // 86400))
except Exception:
    print(0)
PYEOF
        )
    fi
fi

# Severity tier.
severity="OK"
if [[ "$is_pending" -eq 1 ]]; then
    if [[ "$days_pending" -ge $((sla_days * 2)) ]]; then
        severity="CRITICAL"
    elif [[ "$days_pending" -ge "$sla_days" ]]; then
        severity="WARN"
    else
        severity="PENDING"
    fi
fi

# ----- Scan transcripts for recent rejection patterns -----

# Find the project slug for this repo (Claude Code stores transcripts under
# ~/.claude/projects/<dashed-path>/<uuid>.jsonl). We search across all
# project slugs, not just the current one — rejections may have happened
# from other invocations.
declare -a snippets=()
if [[ -d "$transcripts_dir" ]]; then
    # Collect up to 20 most recently modified jsonl files.
    while IFS= read -r jsonl; do
        [[ -f "$jsonl" ]] || continue
        # Grep for the agent name + rejection pattern. -n gives line numbers.
        # We anchor on agent_name to reduce noise. Limit per-file.
        matches="$(grep -niE "(${agent_name}).*(BLOQUEANTE|rechazado|rejected|blocked|no aprueba)|((BLOQUEANTE|rechazado|rejected|blocked|no aprueba).*${agent_name})" "$jsonl" 2>/dev/null | head -3 || true)"
        [[ -z "$matches" ]] && continue
        # Extract session uuid from filename.
        session_uuid="$(basename "$jsonl" .jsonl)"
        # File mtime as date (portable: stat -f on macOS, stat -c on GNU).
        mtime=""
        if stat -f "%Sm" -t "%Y-%m-%d" "$jsonl" >/dev/null 2>&1; then
            mtime="$(stat -f "%Sm" -t "%Y-%m-%d" "$jsonl")"
        elif stat -c "%y" "$jsonl" >/dev/null 2>&1; then
            mtime="$(stat -c "%y" "$jsonl" | cut -d' ' -f1)"
        else
            mtime="unknown"
        fi
        while IFS= read -r match_line; do
            [[ -z "$match_line" ]] && continue
            # Trim to 200 chars to keep snippet manageable.
            snippet="$(printf '%s' "$match_line" | cut -c1-200)"
            snippets+=("${mtime}|${session_uuid:0:8}|${snippet}")
            if [[ "${#snippets[@]}" -ge "$limit" ]]; then
                break 2
            fi
        done <<<"$matches"
    done < <(find "$transcripts_dir" -name '*.jsonl' -type f 2>/dev/null \
        | xargs -I{} stat -f "%m %N" "{}" 2>/dev/null \
        | sort -rn \
        | head -20 \
        | awk '{$1=""; sub(/^ /, ""); print}')
fi

# ----- Emit output -----

if [[ "$json_mode" -eq 1 ]]; then
    snippets_json="$(printf '%s\n' "${snippets[@]:-}" \
        | awk -F'|' 'NF >= 3 {
            date=$1; uuid=$2; snip=$3
            for (i=4; i<=NF; i++) snip = snip "|" $i
            gsub(/\\/, "\\\\", snip); gsub(/"/, "\\\"", snip)
            printf("{\"date\":\"%s\",\"session\":\"%s\",\"snippet\":\"%s\"}\n", date, uuid, snip)
        }' \
        | jq -s '.' 2>/dev/null || echo '[]')"
    [[ -z "$snippets_json" || "$snippets_json" == "null" ]] && snippets_json='[]'

    jq -n \
        --arg agent "$agent_name" \
        --argjson rejections "$rejections" \
        --arg pending_since "$pending_since" \
        --argjson days_pending "$days_pending" \
        --arg severity "$severity" \
        --arg prompt_path "${prompt_path#$REPO_ROOT/}" \
        --argjson recent "$snippets_json" \
        '{
            agent: $agent,
            rejections: $rejections,
            pending_since: $pending_since,
            days_pending: $days_pending,
            severity: $severity,
            prompt_path: $prompt_path,
            recent_rejections: $recent
        }'
    exit 0
fi

# Plain output.
printf '=== Auto-tune review: @%s ===\n' "$agent_name"
printf '  rejections:    %s\n' "$rejections"
if [[ -n "$pending_since" && "$pending_since" != "null" ]]; then
    printf '  pending_since: %s (%sd)\n' "$pending_since" "$days_pending"
else
    printf '  pending_since: (no timestamp — predates ADR-041 or already resolved)\n'
fi
printf '  severity:      %s' "$severity"
case "$severity" in
    CRITICAL) printf ' (>= %dd, 2× SLA)\n' $((sla_days * 2)) ;;
    WARN) printf ' (>= %dd, SLA)\n' "$sla_days" ;;
    PENDING) printf ' (< %dd, within SLA)\n' "$sla_days" ;;
    *) printf '\n' ;;
esac
printf '  prompt path:   %s\n' "${prompt_path#$REPO_ROOT/}"
printf '\n'

if [[ "${#snippets[@]}" -eq 0 ]]; then
    printf 'Recent rejection patterns: none found in last 20 transcripts.\n'
    printf '  (Older transcripts may contain them; this is best-effort.)\n'
else
    printf 'Recent rejection patterns (up to %d):\n' "$limit"
    for snip in "${snippets[@]}"; do
        IFS='|' read -r d u rest <<<"$snip"
        printf '  [%s] session %s — %s\n' "$d" "$u" "$rest"
    done
fi

printf '\nNext step (HITL):\n'
printf '  Paste the above into @prompt-engineer context. ⟦ user_name ⟧ decides the edit;\n'
printf '  the existing reset-on-hash-change in critic-feedback-tracker.sh clears\n'
printf '  the flag automatically when %s changes.\n' "${prompt_path#$REPO_ROOT/}"

exit 0
