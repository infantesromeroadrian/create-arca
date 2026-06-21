#!/bin/bash
# ARCA — Engram Pattern Detector (Hermes Idea 2, Phase G research item)
#
# Reads the last N observations for the current project from the local
# Engram SQLite database, clusters them by topic_key (preferred) or by
# keyword extracted from the title (fallback), and emits a JSON array of
# clusters whose count crosses MIN_CLUSTER_COUNT.
#
# Why this exists. engram-spaced-repetition.sh fires a single random old
# observation at session start. That is muestra random, not pattern
# detection. The morning briefing benefits from the *recurring* themes
# ⟦ user_name ⟧ touches week over week — items he keeps re-deciding, debt that
# does not get closed, areas with concentrated activity. This script is
# the cheap deterministic clustering step. The expensive LLM-as-judge
# review of each cluster lives in `engram-nudge-judge.sh`.
#
# Output contract (stdout): a JSON array. Each element:
#   {
#     "topic":         "<topic_key or derived keyword>",
#     "count":         <integer>,
#     "obs_ids":       [<id>, <id>, ...],
#     "sample_titles": ["<title1>", "<title2>", "<title3>"]
#   }
#
# When there is nothing to report (no DB, no observations, no cluster
# above threshold) the script emits an empty array `[]` and exits 0.
# Failure modes that matter to the caller (sqlite missing, jq missing)
# also yield `[]` and a one-line stderr note — fail-open is safe here
# because the worst outcome is "no nudges this week", not data loss.
#
# Invariants:
#   - Project scope mandatory. Never read across projects.
#   - Stopwords filtered out so "the/and/we/our" do not pretend to be
#     topics. List is conservative English + Spanish short words common
#     in ⟦ user_name ⟧'s notes.
#   - Title cap 200 chars to keep sample_titles bounded for downstream
#     prompt sizes.

set -uo pipefail

DB="${ENGRAM_DB:-${HOME}/.engram/engram.db}"
WINDOW="${ENGRAM_PATTERN_WINDOW:-30}"
MIN_CLUSTER_COUNT="${ENGRAM_PATTERN_MIN_COUNT:-3}"

emit_empty() { printf '[]\n'; exit 0; }

# Hard dependencies. jq is mandatory; we build JSON with it. Without
# sqlite3 we obviously cannot read Engram.
command -v sqlite3 >/dev/null 2>&1 || { echo "[engram-pattern] sqlite3 missing" >&2; emit_empty; }
command -v jq      >/dev/null 2>&1 || { echo "[engram-pattern] jq missing"      >&2; emit_empty; }
[[ -f "$DB" ]] || emit_empty

# Project resolution mirrors engram-spaced-repetition.sh on purpose: same
# slug source, same sanitization. Cross-project leakage would defeat the
# point of nudging on ⟦ user_name ⟧'s *current* work. ENGRAM_PATTERN_PROJECT
# overrides for tests where we want to inject a synthetic dataset.
project="${ENGRAM_PATTERN_PROJECT:-}"
if [[ -z "$project" ]]; then
    if remote_url=$(git config --get remote.origin.url 2>/dev/null); then
        project=$(basename "${remote_url%.git}")
    fi
    [[ -z "$project" ]] && project=$(basename "${PWD}")
fi
project=$(printf '%s' "$project" | tr -cd 'A-Za-z0-9_.-')
[[ -z "$project" ]] && emit_empty

# US (\x1f) separator survives any whitespace inside titles/topic_keys.
rows=$(sqlite3 -separator $'\x1f' "$DB" "
    SELECT id,
           COALESCE(topic_key, ''),
           COALESCE(type, ''),
           COALESCE(replace(replace(title, char(10), ' '), char(9), ' '), '')
    FROM observations
    WHERE project = '$project'
      AND deleted_at IS NULL
    ORDER BY created_at DESC
    LIMIT $WINDOW
" 2>/dev/null)

[[ -z "$rows" ]] && emit_empty

# Stopwords. Conservative — anything you would not want to see as a
# nudge headline. Mixed EN/ES because ⟦ user_name ⟧'s Engram is bilingual.
# Tokens shorter than 4 chars are also discarded by the awk filter
# below, which catches "the", "and", "for", "que", "con" etc. without
# enumerating them. This list covers 4+ char noise that survives the
# length filter.
STOPWORDS="$(cat <<'EOF'
about above after again against because before being below between both could doing during each from further have having here itself just more most other ourselves should some such than that them then there these they this those through under until very were what when where which while will with would your yours yourself yourselves
acerca aunque cada como cuando donde entonces hace hacia hasta luego mientras nunca otra otro para pero porque pues sobre tambien tampoco tanto tener tiene tienen todos
EOF
)"

declare -A cluster_count
declare -A cluster_ids
declare -A cluster_titles

# Record Separator (RS, \x1e) bound to a variable. Inline $'\x1e' inside
# `${var:+...}` parameter expansion is NOT re-evaluated as ANSI-C quoting
# — bash treats it literally, which silently corrupts the sample buffer.
# Bind once, reference everywhere.
RS=$'\x1e'

# Tokenize a title into lowercase >=4-char alphanumeric words, filter
# stopwords, emit one token per line. UTF-8 accented chars are stripped
# (tr -cd 'a-z0-9 ') which is intentional: keeps the script ASCII-safe
# at the cost of degrading "diseño" to "dise". Imperfect but consistent
# across calls — the same input always yields the same key.
# Tracked as ARCA-DEBT-002: replace with `iconv -f utf-8 -t ascii//TRANSLIT`
# upstream of tr to preserve accented projects/topics (Spanish/French).
tokenize() {
    printf '%s' "$1" \
        | tr '[:upper:]' '[:lower:]' \
        | tr -cd 'a-z0-9 \n' \
        | tr -s ' ' '\n' \
        | awk -v sw="$STOPWORDS" '
            BEGIN {
                n = split(sw, a, /[[:space:]]+/);
                for (i = 1; i <= n; i++) stop[a[i]] = 1;
            }
            length($0) >= 4 && !($0 in stop) { print }
        '
}

trim_title() {
    local raw="$1"
    printf '%s' "${raw:0:200}"
}

# Helper: append obs_id + title sample to a cluster bucket, capped at 3
# sample titles. Title list is \x1e (RS, ASCII 30) separated to dodge
# whitespace inside titles.
record_cluster() {
    local key="$1" obs_id="$2" title="$3"
    cluster_count[$key]=$(( ${cluster_count[$key]:-0} + 1 ))
    cluster_ids[$key]="${cluster_ids[$key]:-}${cluster_ids[$key]:+,}$obs_id"
    local existing="${cluster_titles[$key]:-}"
    local sample_count
    sample_count=$(printf '%s' "$existing" | tr "$RS" '\n' | grep -c . || true)
    if (( sample_count < 3 )); then
        local trimmed
        trimmed=$(trim_title "$title")
        cluster_titles[$key]="${existing}${existing:+$RS}${trimmed}"
    fi
}

# shellcheck disable=SC2034 # obs_type read for schema fidelity (future cluster filter)
while IFS=$'\x1f' read -r obs_id topic_key obs_type title; do
    [[ -z "$obs_id" ]] && continue

    # Pass 1: explicit topic_key. Lowercase + sanitize so two notes
    # tagged "Engram-Pattern" and "engram pattern" land in the same
    # bucket.
    if [[ -n "$topic_key" ]]; then
        key=$(printf '%s' "$topic_key" | tr '[:upper:]' '[:lower:]' \
            | tr -cd 'a-z0-9-_ ' | tr -s ' ' '-')
        if [[ -n "$key" ]]; then
            record_cluster "$key" "$obs_id" "$title"
            continue
        fi
    fi

    # Pass 2: derive a single keyword from the title. Take the first
    # non-stopword token >=4 chars. "First" not "most frequent" because
    # titles are short (1-2 informative words). If a title has no
    # informative token we drop the row — clustering on an empty key
    # would group unrelated noise together.
    keyword=$(tokenize "$title" | head -1)
    [[ -z "$keyword" ]] && continue
    record_cluster "$keyword" "$obs_id" "$title"
done <<< "$rows"

# Build JSON. jq's --arg / --argjson keep escaping correct for any
# title content (quotes, backslashes, dollars).
result='[]'
for topic in "${!cluster_count[@]}"; do
    count=${cluster_count[$topic]}
    (( count >= MIN_CLUSTER_COUNT )) || continue

    ids_csv=${cluster_ids[$topic]}
    ids_json=$(printf '%s' "$ids_csv" | jq -Rc 'split(",") | map(tonumber)')

    titles_blob=${cluster_titles[$topic]:-}
    titles_json=$(printf '%s' "$titles_blob" | tr "$RS" '\n' \
        | jq -Rsc 'split("\n") | map(select(length > 0))')

    cluster_json=$(jq -nc \
        --arg topic "$topic" \
        --argjson count "$count" \
        --argjson ids "$ids_json" \
        --argjson titles "$titles_json" \
        '{topic: $topic, count: $count, obs_ids: $ids, sample_titles: $titles}')

    result=$(printf '%s' "$result" | jq -c --argjson c "$cluster_json" '. + [$c]')
done

# Sort descending by count so the caller sees the strongest signals
# first without re-sorting.
printf '%s' "$result" | jq -c 'sort_by(-.count)'
exit 0
