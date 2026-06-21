#!/usr/bin/env bash
# /next-task — read canonical backlog and emit next prioritized entry.
#
# Implements ADR-040 §3 (next-task skill). Pure read-only consumer: parses
# `<project>/docs/c1-discovery/backlog.md`, filters to MoSCoW classes the
# operator asked for, drops entries whose dependencies are not yet resolved,
# sorts by RICE descending, and emits JSON (default) or plain text.

set -uo pipefail

# ----- Argument parsing -----

backlog_path=""
completed_csv=""
moscow_csv="MUST,SHOULD,COULD"
top_n=1
plain_mode=0

usage() {
    cat <<'EOF'
Usage: next-task [--backlog=PATH] [--completed=BL-NNN,...]
                 [--moscow=MUST,SHOULD,COULD] [--top=N] [--plain]

Reads the canonical backlog at <cwd>/docs/c1-discovery/backlog.md (or PATH
via --backlog) and emits the next prioritized entry as JSON.

Exit codes:
  0 — success (results may be empty if nothing is unblocked)
  1 — backlog path missing, jq missing, or argument error
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --backlog=*) backlog_path="${1#--backlog=}" ;;
        --completed=*) completed_csv="${1#--completed=}" ;;
        --moscow=*) moscow_csv="${1#--moscow=}" ;;
        --top=*) top_n="${1#--top=}" ;;
        --plain) plain_mode=1 ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'next-task: unknown arg %q\n' "$1" >&2; usage >&2; exit 1 ;;
    esac
    shift
done

if ! command -v jq >/dev/null 2>&1; then
    printf 'next-task: jq required for JSON output, install with `brew install jq`\n' >&2
    exit 1
fi

if ! [[ "$top_n" =~ ^[0-9]+$ ]] || [[ "$top_n" -lt 1 ]]; then
    printf 'next-task: --top must be a positive integer (got %q)\n' "$top_n" >&2
    exit 1
fi

# Resolve backlog path.
if [[ -z "$backlog_path" ]]; then
    backlog_path="${PWD}/docs/c1-discovery/backlog.md"
fi
if [[ ! -f "$backlog_path" ]]; then
    printf 'next-task: backlog not found at %q\n' "$backlog_path" >&2
    printf 'Try --backlog=PATH or run from project root.\n' >&2
    exit 1
fi

# Build set of completed IDs from CSV.
declare -a completed_ids=()
if [[ -n "$completed_csv" ]]; then
    IFS=',' read -ra parts <<<"$completed_csv"
    for p in "${parts[@]}"; do
        p="${p## }"; p="${p%% }"
        [[ -z "$p" ]] && continue
        completed_ids+=("$p")
    done
fi

# Build allowed MoSCoW classes set.
declare -a moscow_allowed=()
IFS=',' read -ra parts <<<"$moscow_csv"
for p in "${parts[@]}"; do
    p="${p## }"; p="${p%% }"
    case "$p" in
        MUST|SHOULD|COULD) moscow_allowed+=("$p") ;;
        WONT|"WON'T") : ;;  # Always excluded.
        *) printf 'next-task: invalid --moscow value %q (allowed: MUST/SHOULD/COULD)\n' "$p" >&2; exit 1 ;;
    esac
done

in_set() {
    local needle="$1"
    shift
    local item
    for item in "$@"; do
        [[ "$needle" == "$item" ]] && return 0
    done
    return 1
}

dep_is_resolved() {
    local dep="$1"
    [[ "${#completed_ids[@]}" -eq 0 ]] && return 1
    in_set "$dep" "${completed_ids[@]}"
}

# Expand a deps cell into newline-separated BL-NNN tokens. Range
# `BL-001..BL-005` becomes the inclusive enumeration.
expand_deps() {
    local cell="$1"
    [[ -z "$cell" || "$cell" == "—" || "$cell" == "-" ]] && return 0
    IFS=',' read -ra parts <<<"$cell"
    local part left right left_n right_n n
    for part in "${parts[@]}"; do
        part="${part## }"; part="${part%% }"
        if [[ "$part" == *..* ]]; then
            left="${part%%..*}"
            right="${part##*..}"
            left_n="$(printf '%s' "$left" | sed 's/^BL-0*//')"
            right_n="$(printf '%s' "$right" | sed 's/^BL-0*//')"
            [[ -z "$left_n" ]] && left_n=0
            [[ -z "$right_n" ]] && right_n=0
            n="$left_n"
            while [[ "$n" -le "$right_n" ]]; do
                printf 'BL-%03d\n' "$n"
                n=$(( n + 1 ))
            done
        else
            [[ -n "$part" ]] && printf '%s\n' "$part"
        fi
    done
}

# ----- Parse backlog -----

# Collect entries as TSV lines: id\tmoscow\trice\ttitle\ttype\tcycle\tstory_pts\tdeps_csv\tdeps_resolved
entries_tsv="$(mktemp)"
trap 'rm -f "$entries_tsv"' EXIT

current_section=""
while IFS= read -r raw_line; do
    if [[ "$raw_line" =~ ^\#\#\#[[:space:]]+([Mm][Uu][Ss][Tt]) ]]; then
        current_section="MUST"; continue
    elif [[ "$raw_line" =~ ^\#\#\#[[:space:]]+([Ss][Hh][Oo][Uu][Ll][Dd]) ]]; then
        current_section="SHOULD"; continue
    elif [[ "$raw_line" =~ ^\#\#\#[[:space:]]+([Cc][Oo][Uu][Ll][Dd]) ]]; then
        current_section="COULD"; continue
    elif [[ "$raw_line" =~ ^\#\#\#[[:space:]]+([Ww][Oo][Nn].[Tt]) ]]; then
        current_section="WONT"; continue
    elif [[ "$raw_line" =~ ^\#\# ]]; then
        current_section=""; continue
    fi

    [[ -z "$current_section" || "$current_section" == "WONT" ]] && continue
    [[ "$raw_line" != \|* ]] && continue
    [[ "$raw_line" == *"---"* ]] && continue
    [[ "$raw_line" =~ \|[[:space:]]*ID[[:space:]]*\| ]] && continue

    IFS='|' read -ra cells <<<"$raw_line"
    row=()
    cells_len="${#cells[@]}"
    i=1
    while [[ $i -lt $cells_len ]]; do
        c="${cells[$i]}"
        c="${c## }"; c="${c%% }"
        row+=("$c")
        i=$(( i + 1 ))
    done
    while [[ "${#row[@]}" -gt 0 ]]; do
        last_idx=$(( ${#row[@]} - 1 ))
        if [[ -z "${row[$last_idx]}" ]]; then
            unset "row[$last_idx]"
        else
            break
        fi
    done

    [[ "${#row[@]}" -ne 11 ]] && continue
    [[ ! "${row[0]}" =~ ^BL-[0-9]{3}$ ]] && continue

    id_v="${row[0]}"
    title_v="${row[1]}"
    type_v="${row[2]}"
    cycle_v="${row[3]}"
    sp_v="${row[4]}"
    rice_v="${row[9]}"
    deps_v="${row[10]}"

    if ! in_set "$current_section" "${moscow_allowed[@]}"; then
        continue
    fi

    # Items already in --completed are out of the candidate pool: the operator
    # asked "what's next", not "what's the highest RICE in general".
    if [[ "${#completed_ids[@]}" -gt 0 ]] && in_set "$id_v" "${completed_ids[@]}"; then
        continue
    fi

    # Compute deps_resolved.
    resolved="true"
    deps_expanded=""
    while IFS= read -r dep; do
        [[ -z "$dep" ]] && continue
        deps_expanded="${deps_expanded}${dep},"
        if ! dep_is_resolved "$dep"; then
            resolved="false"
        fi
    done < <(expand_deps "$deps_v")
    deps_expanded="${deps_expanded%,}"

    # TSV: id, moscow, rice, title, type, cycle, story_pts, deps_csv, deps_resolved.
    # Empty deps replaced with `_NONE_` because bash `read` collapses consecutive
    # tab whitespace into a single separator. Decoded back at output time.
    deps_field="${deps_expanded:-_NONE_}"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$id_v" "$current_section" "$rice_v" "$title_v" "$type_v" "$cycle_v" "$sp_v" "$deps_field" "$resolved" \
        >>"$entries_tsv"
done <"$backlog_path"

# Filter by deps_resolved=true, sort by RICE desc, truncate to top_n.
filtered_tsv="$(mktemp)"
trap 'rm -f "$entries_tsv" "$filtered_tsv"' EXIT
awk -F'\t' '$9 == "true"' "$entries_tsv" \
    | sort -t$'\t' -k3,3 -g -r \
    | head -n "$top_n" >"$filtered_tsv"

# ----- Emit output -----

if [[ "$plain_mode" -eq 1 ]]; then
    if [[ ! -s "$filtered_tsv" ]]; then
        printf 'No eligible entry — every candidate has unresolved dependencies.\n'
        exit 0
    fi
    while IFS=$'\t' read -r id_v moscow_v rice_v title_v type_v cycle_v sp_v deps_v _resolved; do
        printf '%s [%s · RICE %s] %s\n' "$id_v" "$moscow_v" "$rice_v" "$title_v"
        printf '  type=%s cycle=%s story-pts=%s\n' "$type_v" "$cycle_v" "$sp_v"
        if [[ "$deps_v" != "_NONE_" && -n "$deps_v" ]]; then
            printf '  deps=%s\n' "$deps_v"
        fi
    done <"$filtered_tsv"
    exit 0
fi

# JSON output. The `_NONE_` placeholder for empty deps is decoded back to [].
results_json="$(awk -F'\t' '
    BEGIN { print "[" }
    {
        if (NR > 1) print ","
        gsub(/\\/, "\\\\", $4); gsub(/"/, "\\\"", $4)
        deps_arr = ""
        if ($8 != "_NONE_" && $8 != "") {
            n = split($8, dep_parts, ",")
            for (i = 1; i <= n; i++) {
                d = dep_parts[i]
                if (d == "") continue
                if (deps_arr != "") deps_arr = deps_arr ", "
                deps_arr = deps_arr "\"" d "\""
            }
        }
        printf("  {\"id\":\"%s\",\"title\":\"%s\",\"type\":\"%s\",\"cycle\":\"%s\",\"story_pts\":\"%s\",\"moscow\":\"%s\",\"rice\":%s,\"deps\":[%s],\"deps_resolved\":%s}",
               $1, $4, $5, $6, $7, $2, $3, deps_arr, $9)
    }
    END { print ""; print "]" }
' "$filtered_tsv")"

# Build envelope via jq for guaranteed valid output.
completed_json_arr="$(printf '%s\n' "${completed_ids[@]:-}" | jq -R . | jq -s 'map(select(. != ""))')"
moscow_json_arr="$(printf '%s\n' "${moscow_allowed[@]}" | jq -R . | jq -s .)"

jq -n \
    --arg path "$backlog_path" \
    --argjson completed "$completed_json_arr" \
    --argjson moscow "$moscow_json_arr" \
    --argjson top "$top_n" \
    --argjson results "$results_json" \
    '{
        backlog_path: $path,
        criteria: { completed: $completed, moscow: $moscow, top: $top },
        results: $results
    }'

exit 0
