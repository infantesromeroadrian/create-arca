#!/usr/bin/env bash
# /eval-skeleton — Generate a starter evals/scenarios/<agent>/scenario.json.
#
# Implements ADR-042 §3. Introspects agents/<agent>.md and renders a minimal
# scenario.json template ready for human refinement. Refuses to overwrite an
# existing scenario unless --force is set.

set -uo pipefail

# ----- Argument parsing -----

agent_name=""
json_mode=0
force=0

usage() {
    cat <<'EOF'
Usage: eval-skeleton <agent-name> [--json] [--force]

Reads agents/<agent>.md, introspects frontmatter + phase mapping + critic-gate
exempt status, and writes a starter evals/scenarios/<agent>/scenario.json.

Exit codes:
  0 — success
  1 — argument error, missing prompt, scenario collision (without --force),
      unparseable frontmatter, or jq missing
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --json) json_mode=1 ;;
        --force) force=1 ;;
        -h|--help) usage; exit 0 ;;
        --*) printf 'eval-skeleton: unknown flag %q\n' "$1" >&2; usage >&2; exit 1 ;;
        *)
            if [[ -z "$agent_name" ]]; then
                agent_name="$1"
            else
                printf 'eval-skeleton: unexpected positional %q\n' "$1" >&2
                exit 1
            fi
            ;;
    esac
    shift
done

if [[ -z "$agent_name" ]]; then
    printf 'eval-skeleton: <agent-name> required\n' >&2
    usage >&2
    exit 1
fi

# Validate slug shape — no slashes, no traversal.
case "$agent_name" in
    */*|*..*|.*) printf 'eval-skeleton: invalid agent name %q\n' "$agent_name" >&2; exit 1 ;;
esac

if ! command -v jq >/dev/null 2>&1; then
    printf 'eval-skeleton: jq required\n' >&2
    exit 1
fi

# ----- Resolve REPO_ROOT -----

REPO_ROOT="${ARCA_REPO_ROOT:-}"
if [[ -z "$REPO_ROOT" ]]; then
    cur="$PWD"
    while [[ "$cur" != "/" ]]; do
        if [[ -f "$cur/CLAUDE.md" && -d "$cur/agents" && -d "$cur/evals" ]]; then
            REPO_ROOT="$cur"
            break
        fi
        cur="$(dirname "$cur")"
    done
fi
if [[ -z "$REPO_ROOT" ]]; then
    REPO_ROOT="${HOME}/projects/Projects/.claude"
fi

prompt_path="${REPO_ROOT}/agents/${agent_name}.md"
scenario_dir="${REPO_ROOT}/evals/scenarios/${agent_name}"
scenario_path="${scenario_dir}/scenario.json"
run_evals_path="${REPO_ROOT}/evals/run_evals.py"

if [[ ! -f "$prompt_path" ]]; then
    printf 'eval-skeleton: agent prompt not found at %q\n' "$prompt_path" >&2
    exit 1
fi

if [[ -f "$scenario_path" && "$force" -eq 0 ]]; then
    printf 'eval-skeleton: scenario already exists at %q\n' "$scenario_path" >&2
    printf '  Pass --force to overwrite, or delete the file first.\n' >&2
    exit 1
fi

# ----- Parse frontmatter -----
#
# Frontmatter is YAML between two `---` lines at the start of the file.
# We extract simple `key: value` pairs (no nested structures).

# Read until the second --- delimiter.
fm_block="$(awk '
    BEGIN { in_fm = 0; done = 0 }
    /^---[[:space:]]*$/ {
        if (!in_fm && !done) { in_fm = 1; next }
        if (in_fm) { done = 1; exit }
    }
    in_fm { print }
' "$prompt_path")"

if [[ -z "$fm_block" ]]; then
    printf 'eval-skeleton: frontmatter not found in %q (expected --- ... --- at top)\n' "$prompt_path" >&2
    exit 1
fi

extract_fm() {
    # extract_fm <key>  →  value (trimmed, quotes stripped), or empty.
    local key="$1"
    printf '%s\n' "$fm_block" \
        | awk -v k="$key" -F: 'index($0, k ":") == 1 {
            sub("^" k ":[[:space:]]*", "", $0)
            sub("[[:space:]]+$", "", $0)
            # Strip enclosing quotes if any.
            gsub(/^["'\'']|["'\'']$/, "", $0)
            print
            exit
        }'
}

fm_model="$(extract_fm model)"
fm_isolation="$(extract_fm isolation)"
fm_color="$(extract_fm color)"
fm_description="$(extract_fm description)"

# Tools can be inline list `tools: A, B, C` or `tools: [A, B, C]`.
fm_tools="$(extract_fm tools)"
# Strip brackets if present.
fm_tools="${fm_tools#[}"
fm_tools="${fm_tools%]}"

# Validate the required-ish fields. Missing is non-fatal — we emit a partial
# scenario and let run_evals.py surface the gap on its own pass.
[[ -z "$fm_model" ]] && fm_model="opus"
case "$fm_model" in
    opus|sonnet|haiku) : ;;
    *) fm_model="opus" ;;
esac

# ----- Phase mapping + critic-gate exempt from run_evals.py -----
#
# We parse the Python literals defensively. If the file moves or is renamed,
# we fall back to expected_phases=["all"], critic_gate_required=false, and
# warn on stderr.

phases_json='["all"]'
critic_gate_required="true"
phases_warning=""

if [[ -f "$run_evals_path" ]]; then
    # Extract PHASE_AGENTS block; for each cycle key, check if our agent is in
    # the list. Output phases as JSON array.
    phases_json="$(python3 - "$run_evals_path" "$agent_name" <<'PYEOF' 2>/dev/null
import json
import re
import sys

path, agent = sys.argv[1], sys.argv[2]
src = open(path).read()

m = re.search(r"PHASE_AGENTS\s*=\s*\{(.*?)^\}", src, re.S | re.M)
phases = []
if m:
    block = m.group(1)
    # Match: "C1": [...]
    for cm in re.finditer(r'"(C\d+)"\s*:\s*\[(.*?)\]', block, re.S):
        cycle = cm.group(1)
        items = re.findall(r'"([^"]+)"', cm.group(2))
        if agent in items:
            phases.append(cycle)

if not phases:
    phases = ["all"]

print(json.dumps(phases))
PYEOF
    )"
    [[ -z "$phases_json" ]] && phases_json='["all"]'

    # Critic-gate exempt: parse the CRITIC_GATE_EXEMPT set.
    exempt_hit="$(python3 - "$run_evals_path" "$agent_name" <<'PYEOF' 2>/dev/null
import re
import sys

path, agent = sys.argv[1], sys.argv[2]
src = open(path).read()
m = re.search(r"CRITIC_GATE_EXEMPT\s*=\s*\{(.*?)\}", src, re.S)
if m:
    items = re.findall(r'"([^"]+)"', m.group(1))
    print("true" if agent in items else "false")
else:
    print("false")
PYEOF
    )"
    if [[ "$exempt_hit" == "true" ]]; then
        critic_gate_required="false"
    fi
else
    phases_warning="evals/run_evals.py missing — phases default to [\"all\"]"
fi

# ----- Keyword extraction -----
#
# First 5 unique alphabetic tokens of length >= 5 in the prompt BODY (skip
# frontmatter), excluding a small English/Spanish stop-list and excluding
# tokens already present in the frontmatter description.

stoplist=$'about\nafter\nagain\nagainst\nbefore\nbeing\nbetween\nbecause\ncould\ndoing\ndoes\neach\nfrom\nfurther\nhaving\nhere\nhimself\nhould\ninto\nitself\nmore\nmost\nother\nover\nshould\nsome\nsuch\nthan\nthat\nthen\nthere\nthese\nthey\nthis\nthose\nthrough\nunder\nuntil\nvery\nwhat\nwhen\nwhere\nwhich\nwhile\nwith\nwould\nyourself\nantes\ndespues\nentre\ncuando\nporque\ndesde\nhasta\npara\nsobre\nsegun\nseno\nestar\ntener\nhacer\npoder\ncomo\nesta\neste\nestos\nestas\nesto\nellos\nellas\nellos\nuna\nlos\nlas\notra\notro\notras\notros\nname\nmodel\ntools\nuser\nopus\nsonnet\nhaiku'

keywords_json="$(python3 - "$prompt_path" "$fm_description" <<PYEOF 2>/dev/null
import json
import re
import sys

path, descr = sys.argv[1], sys.argv[2]
src = open(path).read()

# Strip frontmatter (first --- ... --- block at file start).
m = re.match(r"^---\s*\n.*?\n---\s*\n", src, re.S)
body = src[m.end():] if m else src

stoplist = set('''$stoplist'''.split())
descr_tokens = set(re.findall(r"[a-zA-Z]{5,}", (descr or "").lower()))

seen = []
seen_set = set()
for tok in re.findall(r"[a-zA-Z][a-zA-Z\-]{4,}", body):
    t = tok.lower()
    # Strip trailing hyphen.
    t = t.strip("-")
    if len(t) < 5: continue
    if t in stoplist or t in descr_tokens: continue
    if t in seen_set: continue
    seen_set.add(t)
    seen.append(t)
    if len(seen) >= 5:
        break

print(json.dumps(seen))
PYEOF
)"
[[ -z "$keywords_json" || "$keywords_json" == "null" ]] && keywords_json='[]'

# ----- Render scenario.json -----

mkdir -p "$scenario_dir"

# Build scenario via jq. TODO markers are visible in both required_keywords
# and the stub case so grep -r "EVAL-SKELETON TODO" finds incomplete files.
todo_marker="EVAL-SKELETON TODO"
description="Structural validation for ${agent_name} — generated by /eval-skeleton; refine TODO markers before relying on this scenario."

scenario_content="$(jq -n \
    --arg agent "$agent_name" \
    --arg description "$description" \
    --arg model "$fm_model" \
    --argjson phases "$phases_json" \
    --argjson critic_gate "$critic_gate_required" \
    --argjson kw "$keywords_json" \
    --arg todo "$todo_marker" \
    '{
        agent: $agent,
        description: $description,
        checks: {
            required_frontmatter: ["name", "description", "model", "isolation", "tools", "color"],
            expected_model: $model,
            expected_phases: $phases,
            critic_gate_required: $critic_gate,
            required_keywords: ($kw + [$todo])
        },
        cases: [
            {
                name: "stub_case_refine_me",
                description: ($todo + ": replace with a specific anti-pattern or required behavior for @\($agent)"),
                expected_keywords_in_prompt: ($kw[:2] + [$todo]),
                validation: "prompt_keyword_check"
            }
        ]
    }')"

printf '%s\n' "$scenario_content" > "$scenario_path"

# ----- Stats bump -----

stats_file="${HOME}/.claude/state/eval-coverage-stats.json"
mkdir -p "$(dirname "$stats_file")"
if [[ -f "$stats_file" ]]; then
    tmp="$(mktemp)"
    jq --arg a "$agent_name" \
       '.skeleton_generated = (.skeleton_generated // 0) + 1
        | .last_skeleton_agent = $a
        | .last_skeleton_at = now' \
        "$stats_file" >"$tmp" 2>/dev/null && mv "$tmp" "$stats_file"
else
    jq -n --arg a "$agent_name" \
        '{advisory_emitted:0, bypass:0, skeleton_generated:1,
          last_skeleton_agent:$a, last_skeleton_at: now}' >"$stats_file"
fi

# ----- Emit output -----

# Count TODO markers in the written scenario for the summary line.
todo_count="$(grep -o "$todo_marker" "$scenario_path" | wc -l | tr -d ' ')"

# Compute relative scenario path for nicer output.
rel_scenario_path="${scenario_path#$REPO_ROOT/}"
rel_prompt_path="${prompt_path#$REPO_ROOT/}"

if [[ "$json_mode" -eq 1 ]]; then
    jq -n \
        --arg agent "$agent_name" \
        --arg scenario_path "$rel_scenario_path" \
        --arg model "$fm_model" \
        --arg isolation "$fm_isolation" \
        --arg color "$fm_color" \
        --argjson phases "$phases_json" \
        --argjson critic_gate "$critic_gate_required" \
        --argjson kw "$keywords_json" \
        --argjson todo_count "$todo_count" \
        --argjson written true \
        '{
            agent: $agent,
            scenario_path: $scenario_path,
            frontmatter: {model: $model, isolation: $isolation, color: $color},
            phases: $phases,
            critic_gate_required: $critic_gate,
            keywords: $kw,
            todo_markers: $todo_count,
            written: $written
        }'
    exit 0
fi

# Plain output.
printf '=== eval-skeleton: @%s ===\n' "$agent_name"
printf '  prompt path:         %s\n' "$rel_prompt_path"
printf '  scenario path:       %s\n' "$rel_scenario_path"
printf '  model (frontmatter): %s\n' "$fm_model"
phases_plain="$(printf '%s' "$phases_json" | jq -r '. | join(", ")')"
printf '  phases detected:     %s\n' "$phases_plain"
printf '  critic_gate_required: %s\n' "$critic_gate_required"
kw_plain="$(printf '%s' "$keywords_json" | jq -r '. | join(", ")')"
[[ -z "$kw_plain" ]] && kw_plain="(none extracted — refine manually)"
printf '  keywords (TODO):     %s\n' "$kw_plain"
[[ -n "$phases_warning" ]] && printf '  warning:             %s\n' "$phases_warning"
printf '\n'
printf 'Wrote %s (%s TODO markers).\n' "$rel_scenario_path" "$todo_count"
printf '\nNext step:\n'
printf '  Open the scenario file and replace [EVAL-SKELETON TODO] markers with\n'
printf '  agent-specific anti-patterns. Then run:  python3 evals/run_evals.py\n'

exit 0
