#!/bin/bash
set -uo pipefail

# Layer-1 schema-floor validator for ARCA Orchestration Proposals (ADR-089).
#
# Rejects a proposal where a node UNDER-DECLARES the mandatory critic set
# for its agent type. The floor lives in the schema's x-node-type-gate-floor
# (single source of truth), so adding an agent to a category is a schema
# edit, not a code edit.
#
# A "required_gates_in_order" check is an ORDERED SUBSEQUENCE: the required
# gates must appear in the node's blocking_gates[] in that relative order
# (gaps allowed). math-producers are also code-producers but get the
# stricter chain; the FIRST matching category wins.
#
# Usage:
#   validate-orchestration-proposal.sh <proposal.json>
# Exit:
#   0 + "PASS ..." on stdout         -> proposal satisfies the floor.
#   1 + one violation per line       -> rejected (⟦ user_name ⟧ never sees it).
#   2 + error message                -> usage / parse error (not a verdict).
#
# Overrides:
#   ARCA_DYNORCH_SCHEMA -> schema path (default: sibling schema file).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCHEMA="${ARCA_DYNORCH_SCHEMA:-${SCRIPT_DIR}/orchestration-proposal-schema.json}"
PROPOSAL="${1:-}"

command -v jq >/dev/null 2>&1 || { echo "[ERROR] jq required" >&2; exit 2; }
[[ -n "$PROPOSAL" && -f "$PROPOSAL" ]] || { echo "[ERROR] usage: $0 <proposal.json>" >&2; exit 2; }
[[ -f "$SCHEMA" ]] || { echo "[ERROR] schema not found: $SCHEMA" >&2; exit 2; }
jq -e . "$PROPOSAL" >/dev/null 2>&1 || { echo "[ERROR] proposal is not valid JSON: $PROPOSAL" >&2; exit 2; }

VIOLATIONS=()
add() { VIOLATIONS+=("$1"); }

# --- Floor data (from schema, single source of truth) ---------------------
MATH_AGENTS=$(jq -r '.["x-node-type-gate-floor"].categories[] | select(.id=="math_producers") | .agents[]' "$SCHEMA")
CODE_AGENTS=$(jq -r '.["x-node-type-gate-floor"].categories[] | select(.id=="code_producers") | .agents[]' "$SCHEMA")
MATH_GATES=$(jq -c '.["x-node-type-gate-floor"].categories[] | select(.id=="math_producers") | .required_gates_in_order' "$SCHEMA")
CODE_GATES=$(jq -c '.["x-node-type-gate-floor"].categories[] | select(.id=="code_producers") | .required_gates_in_order' "$SCHEMA")
DEPLOY_GATES=$(jq -c '.["x-node-type-gate-floor"].flag_rules.produces_deployable.required_gates_in_order' "$SCHEMA")
ADV_GATES=$(jq -c '.["x-node-type-gate-floor"].flag_rules.hits_adversarial_signals.required_gates_in_order' "$SCHEMA")

# Known-agent allowlist, derived from the agents/ directory (single source
# of truth, drift-free). Closes the typo-evasion gap: a misspelled agent
# name (e.g. "ml-enginer") would otherwise match no category and silently
# skip the critic floor. When the roster dir cannot be located we skip this
# check rather than fail closed — the runtime hooks remain the backstop.
AGENTS_DIR="${ARCA_AGENTS_DIR:-${SCRIPT_DIR}/../../agents}"
KNOWN_AGENTS=""
[[ -d "$AGENTS_DIR" ]] && KNOWN_AGENTS=$(find "$AGENTS_DIR" -maxdepth 1 -name '*.md' -exec basename {} .md \; 2>/dev/null)

# ordered_subseq <actual_json_array> <required_json_array> -> exit 0 if
# required is an ordered subsequence of actual.
ordered_subseq() {
  jq -ne --argjson b "$1" --argjson r "$2" \
    'reduce $b[] as $x ({i:0}; if .i < ($r|length) and $x == $r[.i] then {i:.i+1} else . end) | .i == ($r|length)' \
    >/dev/null 2>&1
}

in_set() { printf '%s\n' "$1" | grep -qxF "$2"; }

# --- Top-level structural floor -------------------------------------------
[[ "$(jq -r '.schema_version // empty' "$PROPOSAL")" == "1.0" ]] || add "schema_version must be \"1.0\""
[[ "$(jq -r '.preflight.token_optimizer // empty' "$PROPOSAL")" == "required" ]] || add "preflight.token_optimizer must be \"required\" (preflight is non-skippable)"
[[ "$(jq -r '.preflight.skill_router // empty' "$PROPOSAL")" == "required" ]] || add "preflight.skill_router must be \"required\" (preflight is non-skippable)"

APPROVAL_STATUS=$(jq -r '.approval.status // empty' "$PROPOSAL")
case "$APPROVAL_STATUS" in
  PENDING_⟦ user_name ⟧|APPROVED) : ;;
  *) add "approval.status must be PENDING_⟦ user_name ⟧ or APPROVED (got: '${APPROVAL_STATUS:-<missing>}') — execution is gated on ⟦ user_name ⟧'s approval" ;;
esac

NNODES=$(jq '.nodes | length' "$PROPOSAL" 2>/dev/null || echo 0)
[[ "$NNODES" -ge 1 ]] || add "nodes[] must contain at least one node"

# --- Per-node floor --------------------------------------------------------
HAS_CODE_PRODUCER=0
idx=0
while [[ "$idx" -lt "$NNODES" ]]; do
  AGENT=$(jq -r ".nodes[$idx].agent // empty" "$PROPOSAL")
  NID=$(jq -r ".nodes[$idx].id // \"node[$idx]\"" "$PROPOSAL")
  BG=$(jq -c ".nodes[$idx].blocking_gates // []" "$PROPOSAL")

  if [[ -z "$AGENT" ]]; then
    add "node '$NID' is missing required field 'agent'"
    idx=$((idx + 1)); continue
  fi

  if [[ -n "$KNOWN_AGENTS" ]] && ! in_set "$KNOWN_AGENTS" "$AGENT"; then
    add "node '$NID' references unknown agent '@$AGENT' — not in the roster (typo? see agents/). An unknown agent silently evades the critic floor."
  fi

  if in_set "$MATH_AGENTS" "$AGENT"; then
    HAS_CODE_PRODUCER=1
    ordered_subseq "$BG" "$MATH_GATES" || add "node '$NID' (@$AGENT) must declare blocking_gates ⊇ $(echo "$MATH_GATES" | jq -r 'join(" -> ")') in order — got $(echo "$BG" | jq -c .)"
  elif in_set "$CODE_AGENTS" "$AGENT"; then
    HAS_CODE_PRODUCER=1
    ordered_subseq "$BG" "$CODE_GATES" || add "node '$NID' (@$AGENT) must declare blocking_gates ⊇ $(echo "$CODE_GATES" | jq -r 'join(" -> ")') in order — got $(echo "$BG" | jq -c .)"
  fi

  if [[ "$(jq -r ".nodes[$idx].produces_deployable // false" "$PROPOSAL")" == "true" ]]; then
    ordered_subseq "$BG" "$DEPLOY_GATES" || add "node '$NID' (@$AGENT) produces a deployable -> must declare $(echo "$DEPLOY_GATES" | jq -r 'join(" -> ")') in order"
  fi
  if [[ "$(jq -r ".nodes[$idx].hits_adversarial_signals // false" "$PROPOSAL")" == "true" ]]; then
    ordered_subseq "$BG" "$ADV_GATES" || add "node '$NID' (@$AGENT) hits adversarial signals -> must declare @ai-red-teamer as a blocking gate"
  fi

  idx=$((idx + 1))
done

# --- Global: code-producing DAG must declare a terminal closer ------------
if [[ "$HAS_CODE_PRODUCER" -eq 1 ]]; then
  N_CLOSERS=$(jq '[.nodes[] | select(.is_terminal_closer==true)] | length' "$PROPOSAL" 2>/dev/null || echo 0)
  [[ "$N_CLOSERS" -ge 1 ]] || add "DAG produces code but declares no terminal closer (a node with is_terminal_closer:true) — required so the runtime hook can gate code-critic before the DAG ends (ADR-089 gap fix)"
fi

# --- Verdict ---------------------------------------------------------------
if [[ "${#VIOLATIONS[@]}" -eq 0 ]]; then
  echo "PASS — orchestration proposal satisfies the Layer-1 critic floor ($NNODES nodes)"
  exit 0
fi

echo "REJECTED — ${#VIOLATIONS[@]} floor violation(s):" >&2
for v in "${VIOLATIONS[@]}"; do
  echo "  - $v" >&2
done
exit 1
