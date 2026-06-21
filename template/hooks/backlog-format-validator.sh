#!/usr/bin/env bash
# ARCA — backlog-format-validator (PostToolUse:Edit + PostToolUse:Write)
#
# Implements ADR-040 (Backlog format canonical — MoSCoW + RICE schema).
#
# Fires when the modified path matches `**/docs/c1-discovery/backlog.md`.
# Validates the file against the canonical schema described in ADR-040
# sections 1.1 through 1.10. Exits non-zero with explanatory stderr on
# violations; silent on success.
#
# Skipped silently when:
#   - The modified path does not match the canonical backlog path.
#   - The project basename is in the meta-ecosystem denylist (ADR-037).
#   - ARCA_BACKLOG_VALIDATOR_DISABLE=1 is set.
#
# Stdin: JSON payload with at minimum tool_input.file_path (Edit) or
# tool_input.file_path (Write).

set -uo pipefail

# Read JSON payload from stdin.
payload="$(cat -)"

# Extract the modified file path (jq optional — fallback: silent skip).
if command -v jq >/dev/null 2>&1; then
    file_path="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty' 2>/dev/null || echo "")"
    cwd="$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null || echo "$PWD")"
else
    exit 0
fi

# Bypass via env var.
if [[ "${ARCA_BACKLOG_VALIDATOR_DISABLE:-0}" == "1" ]]; then
    exit 0
fi

# Path filter — only operate on the canonical backlog path.
case "$file_path" in
    */docs/c1-discovery/backlog.md) : ;;
    *) exit 0 ;;
esac

# Denylist meta-ecosystem repos (composes with ADR-037).
denylist_file="${HOME}/.claude/hooks/lib/phase-state-denylist.txt"
project_basename="$(basename "${cwd:-$PWD}")"
if [[ -f "$denylist_file" ]] && grep -qE "^${project_basename}$" "$denylist_file" 2>/dev/null; then
    exit 0
fi

# File must exist (race with deletes/renames).
if [[ ! -f "$file_path" ]]; then
    exit 0
fi

# ----- Validation -----

violations=()

# Closed enums (ADR-040 sections 1.3, 1.4, 1.8, 1.9).
type_enum="Data Model Infra Eval Docs Spike Integration Security UI"
cycle_enum="C1 C2 C3 C4 C5 C6 C7 C8 C9 C10 C11 C12 C13 C14"
impact_enum="3 2 1 0.5 0.25"
fib_enum="1 2 3 5 8 13"

# Confidence is checked as a numeric in [0, 1] rather than a closed set.
# The voice/ empirical reference uses 0.6, 0.7, 0.9 alongside 1.0/0.8/0.5;
# RICE in the wild allows continuous confidence. ADR-040 1.8 documents this.
validate_confidence() {
    local cell="$1"
    [[ "$cell" =~ ^(0(\.[0-9]+)?|1(\.0+)?)$ ]] || return 1
    return 0
}

in_set() {
    local needle="$1"
    shift
    local item
    for item in "$@"; do
        [[ "$needle" == "$item" ]] && return 0
    done
    return 1
}

# Validate Type cell — accepts "Data" or "Data/Infra" (slash-separated combos).
validate_type() {
    local cell="$1"
    local part
    IFS='/' read -ra parts <<<"$cell"
    for part in "${parts[@]}"; do
        part="${part## }"
        part="${part%% }"
        if ! in_set "$part" $type_enum; then
            return 1
        fi
    done
    return 0
}

# Validate Cycle cell — accepts "C1" or "C1→C4" (Unicode arrow).
validate_cycle() {
    local cell="$1"
    if [[ "$cell" == *"→"* ]]; then
        local left="${cell%%→*}"
        local right="${cell##*→}"
        left="${left## }"; left="${left%% }"
        right="${right## }"; right="${right%% }"
        in_set "$left" $cycle_enum && in_set "$right" $cycle_enum
        return $?
    fi
    in_set "$cell" $cycle_enum
    return $?
}

# Validate Story-points cell — accepts "1" or "2-3" (Fibonacci endpoints).
validate_story_pts() {
    local cell="$1"
    if [[ "$cell" == *-* ]]; then
        local left="${cell%-*}"
        local right="${cell#*-}"
        left="${left## }"; left="${left%% }"
        right="${right## }"; right="${right%% }"
        in_set "$left" $fib_enum && in_set "$right" $fib_enum
        return $?
    fi
    in_set "$cell" $fib_enum
    return $?
}

# Track all declared IDs and all referenced deps for cross-check.
declare -a declared_ids=()
declare -a referenced_deps=()

current_section=""
# ADR-046: removed dead-code flags `seen_should/seen_could/seen_wont` that
# were assigned but never read. Only `seen_must` is enforced (line ~302).
seen_must=0
line_no=0

while IFS= read -r raw_line; do
    line_no=$((line_no + 1))

    # Detect MoSCoW section headers (case-insensitive on first letter only).
    if [[ "$raw_line" =~ ^\#\#\#[[:space:]]+([Mm][Uu][Ss][Tt]) ]]; then
        current_section="MUST"
        seen_must=1
        continue
    elif [[ "$raw_line" =~ ^\#\#\#[[:space:]]+([Ss][Hh][Oo][Uu][Ll][Dd]) ]]; then
        current_section="SHOULD"
        continue
    elif [[ "$raw_line" =~ ^\#\#\#[[:space:]]+([Cc][Oo][Uu][Ll][Dd]) ]]; then
        current_section="COULD"
        continue
    elif [[ "$raw_line" =~ ^\#\#\#[[:space:]]+([Ww][Oo][Nn].[Tt]) ]]; then
        current_section="WONT"
        continue
    elif [[ "$raw_line" =~ ^\#\# ]]; then
        # Higher-level section (## ...) — leave the MoSCoW context.
        current_section=""
        continue
    fi

    # Process table data rows only when inside a MoSCoW section.
    [[ -z "$current_section" ]] && continue

    # Skip non-table lines.
    [[ "$raw_line" != \|* ]] && continue
    # Skip header/separator rows.
    [[ "$raw_line" == *"---"* ]] && continue
    [[ "$raw_line" =~ \|[[:space:]]*ID[[:space:]]*\| ]] && continue

    # Split row into trimmed cells. Bash's `read -a` may or may not emit a
    # trailing empty after a terminal `|` depending on version + newlines, so
    # we trim trailing empties defensively after the split.
    IFS='|' read -ra cells <<<"$raw_line"
    row=()
    cells_len="${#cells[@]}"
    # Skip leading empty (cells[0] when line starts with |).
    i=1
    while [[ $i -lt $cells_len ]]; do
        c="${cells[$i]}"
        c="${c## }"; c="${c%% }"
        row+=("$c")
        i=$(( i + 1 ))
    done
    # Pop trailing empty cell (artifact of terminal | when bash kept it).
    while [[ "${#row[@]}" -gt 0 ]]; do
        last_idx=$(( ${#row[@]} - 1 ))
        if [[ -z "${row[$last_idx]}" ]]; then
            unset "row[$last_idx]"
        else
            break
        fi
    done

    if [[ "$current_section" == "WONT" ]]; then
        # Reduced schema: ID | Title | Reason — exactly 3 cells.
        if [[ "${#row[@]}" -ne 3 ]]; then
            violations+=("L${line_no} WON'T row must have 3 cells (ID, Title, Reason); got ${#row[@]}")
            continue
        fi
        local_id="${row[0]}"
        if ! [[ "$local_id" =~ ^BL-[0-9]{3}$ ]]; then
            violations+=("L${line_no} ID '${local_id}' does not match BL-NNN")
        else
            declared_ids+=("$local_id")
        fi
        continue
    fi

    # MUST / SHOULD / COULD: 11-cell schema.
    if [[ "${#row[@]}" -ne 11 ]]; then
        violations+=("L${line_no} ${current_section} row must have 11 cells; got ${#row[@]}")
        continue
    fi

    id_cell="${row[0]}"
    type_cell="${row[2]}"
    cycle_cell="${row[3]}"
    sp_cell="${row[4]}"
    impact_cell="${row[6]}"
    conf_cell="${row[7]}"
    effort_cell="${row[8]}"
    rice_cell="${row[9]}"
    deps_cell="${row[10]}"

    # ID
    if ! [[ "$id_cell" =~ ^BL-[0-9]{3}$ ]]; then
        violations+=("L${line_no} ID '${id_cell}' does not match BL-NNN")
    else
        declared_ids+=("$id_cell")
    fi

    # Type
    if ! validate_type "$type_cell"; then
        violations+=("L${line_no} ${id_cell} Type '${type_cell}' not in enum")
    fi

    # Cycle
    if ! validate_cycle "$cycle_cell"; then
        violations+=("L${line_no} ${id_cell} Cycle '${cycle_cell}' not in enum")
    fi

    # Story points
    if ! validate_story_pts "$sp_cell"; then
        violations+=("L${line_no} ${id_cell} Story pts '${sp_cell}' not Fibonacci 1/2/3/5/8/13")
    fi

    # Impact
    if ! in_set "$impact_cell" $impact_enum; then
        violations+=("L${line_no} ${id_cell} Impact '${impact_cell}' not in {3, 2, 1, 0.5, 0.25}")
    fi

    # Confidence — numeric in [0, 1].
    if ! validate_confidence "$conf_cell"; then
        violations+=("L${line_no} ${id_cell} Confidence '${conf_cell}' must be numeric in [0, 1]")
    fi

    # Effort: positive number.
    if ! [[ "$effort_cell" =~ ^[0-9]+(\.[0-9]+)?$ ]] || [[ "$effort_cell" == "0" || "$effort_cell" == "0.0" ]]; then
        violations+=("L${line_no} ${id_cell} Effort '${effort_cell}' must be positive number (person-days)")
    fi

    # RICE: positive number.
    if ! [[ "$rice_cell" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        violations+=("L${line_no} ${id_cell} RICE '${rice_cell}' must be positive number")
    fi

    # Deps: parse refs (commas + ranges).
    if [[ -n "$deps_cell" && "$deps_cell" != "—" && "$deps_cell" != "-" ]]; then
        IFS=',' read -ra dep_parts <<<"$deps_cell"
        for dep in "${dep_parts[@]}"; do
            dep="${dep## }"; dep="${dep%% }"
            if [[ "$dep" == *..* ]]; then
                # Range BL-001..BL-005.
                left_dep="${dep%%..*}"
                right_dep="${dep##*..}"
                if ! [[ "$left_dep" =~ ^BL-[0-9]{3}$ ]] || ! [[ "$right_dep" =~ ^BL-[0-9]{3}$ ]]; then
                    violations+=("L${line_no} ${id_cell} Deps range '${dep}' malformed")
                    continue
                fi
                left_n="${left_dep#BL-}"; left_n="${left_n#0}"; left_n="${left_n#0}"
                right_n="${right_dep#BL-}"; right_n="${right_n#0}"; right_n="${right_n#0}"
                if [[ -z "$left_n" ]]; then left_n=0; fi
                if [[ -z "$right_n" ]]; then right_n=0; fi
                local_n="$left_n"
                while [[ "$local_n" -le "$right_n" ]]; do
                    referenced_deps+=("$(printf 'BL-%03d' "$local_n")")
                    local_n=$((local_n + 1))
                done
            else
                if ! [[ "$dep" =~ ^BL-[0-9]{3}$ ]]; then
                    violations+=("L${line_no} ${id_cell} Deps token '${dep}' not BL-NNN")
                else
                    referenced_deps+=("$dep")
                fi
            fi
        done
    fi
done <"$file_path"

# At minimum MUST must be present.
if [[ "$seen_must" -eq 0 ]]; then
    violations+=("missing required '### MUST' section")
fi

# Cross-check deps reference declared IDs.
if [[ "${#referenced_deps[@]}" -gt 0 && "${#declared_ids[@]}" -gt 0 ]]; then
    for dep in "${referenced_deps[@]}"; do
        found=0
        for id in "${declared_ids[@]}"; do
            if [[ "$dep" == "$id" ]]; then
                found=1
                break
            fi
        done
        if [[ "$found" -eq 0 ]]; then
            violations+=("dep '${dep}' references undeclared ID")
        fi
    done
fi

# Emit violations + persist stats.
stats_file="${HOME}/.claude/state/backlog-format-validator-stats.json"
mkdir -p "$(dirname "$stats_file")"
if [[ "${#violations[@]}" -gt 0 ]]; then
    {
        printf '\n[backlog-format-validator] ADR-040 violations in %s:\n' "$file_path"
        for v in "${violations[@]}"; do
            printf '  - %s\n' "$v"
        done
        printf '\nBypass: ARCA_BACKLOG_VALIDATOR_DISABLE=1 (audit-logged).\n'
    } >&2
    # Update stats (rejected). P0-H2 fix (audit 2026-05-16): atomic via flock.
    if command -v jq >/dev/null 2>&1; then
        (
            flock -w 5 9 || exit 1
            if [[ -f "$stats_file" ]]; then
                tmp="${stats_file}.tmp.$$"
                jq '.rejected = (.rejected // 0) + 1 | .last_rejection = now | .last_rejection_path = $p' \
                    --arg p "$file_path" \
                    "$stats_file" >"$tmp" 2>/dev/null \
                    && mv "$tmp" "$stats_file" \
                    || rm -f "$tmp"
            else
                printf '{"approved":0,"rejected":1,"bypass":0}\n' >"$stats_file"
            fi
        ) 9>"${stats_file}.lock"
    fi
    exit 2
fi

# Update stats (approved). P0-H2 fix (audit 2026-05-16): atomic via flock.
if command -v jq >/dev/null 2>&1; then
    (
        flock -w 5 9 || exit 1
        if [[ -f "$stats_file" ]]; then
            tmp="${stats_file}.tmp.$$"
            jq '.approved = (.approved // 0) + 1' "$stats_file" >"$tmp" 2>/dev/null \
                && mv "$tmp" "$stats_file" \
                || rm -f "$tmp"
        else
            printf '{"approved":1,"rejected":0,"bypass":0}\n' >"$stats_file"
        fi
    ) 9>"${stats_file}.lock"
fi

exit 0
