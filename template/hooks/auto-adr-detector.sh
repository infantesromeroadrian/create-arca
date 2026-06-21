#!/bin/bash
# ARCA — Auto-ADR detector (E.2) — PostToolUse:Agent advisory hook
#
# Closes ARCA mortal sin #4 ("Arquitectura sin ADR / sin justificacion")
# by detecting when @architect-ai output describes an architectural
# decision without a corresponding docs/adr/NNN-*.md file in the same
# turn. When the heuristic fires, emits a stderr nudge inviting the
# operator to run /adr-new. NEVER blocks — advisory mode only.
#
# RATIONALE FOR ADVISORY-ONLY:
#   The detector is heuristic, not deterministic. Hard-blocking on a
#   keyword score would punish legitimate informational outputs from
#   @architect-ai (e.g. summarising existing ADRs). Forced-justification
#   already covers the deterministic 30-LOC / critical-path gate; this
#   hook fills the soft-coverage hole between "narrating an idea" and
#   "documenting a decision".
#
# HEURISTIC (score >= 4 fires the nudge):
#   word                            weight
#   ADR (without ADR-NNN cite)         3
#   supersedes / deprecates            3
#   decision / decided / chose         2
#   trade-?off / tradeoffs             2
#   alternatives / options considered  2
#   architecture / architectural       1
#   rationale / justification          1
#   consequences / implications        1
#
# ANTI-TRIGGER (score -= 5):
#   - Output cites an existing ADR by its number (ADR-001 etc.)
#   - A docs/adr/NNN-*.md file was edited or written in this session
#     within the last 5 minutes (recency window).
#
# RATE-LIMIT:
#   One nudge per (session_id, agent) per hour. Avoids spamming when
#   @architect-ai is invoked repeatedly in the same brainstorming pass.
#
# Test override:
#   ARCA_AUTO_ADR_STATE_DIR — redirect state dir for pytest/shell tests.
#   ARCA_AUTO_ADR_DISABLE_RECENCY=1 — skip the "recent ADR edit" anti-trigger.

set -uo pipefail
umask 077

INPUT=$(cat 2>/dev/null || echo '{}')

command -v jq >/dev/null 2>&1 || exit 0

TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || echo "")
[[ "$TOOL_NAME" != "Agent" ]] && exit 0

SUBAGENT=$(printf '%s' "$INPUT" | jq -r '.tool_input.subagent_type // empty' 2>/dev/null || echo "")
[[ "$SUBAGENT" != "architect-ai" ]] && exit 0

# Operator can mute the advisory for the current session via env var.
# Counted in stats so Guardian Audit notices excessive bypass usage.
if [[ "${ARCA_AUTO_ADR_BYPASS:-}" == "1" ]]; then
    PROJECT_DIR_EARLY="${CLAUDE_PROJECT_DIR:-${PWD}}"
    bash "${PROJECT_DIR_EARLY}/hooks/lib/auto-adr-stats.sh" bypass 2>/dev/null || true
    exit 0
fi

# tool_response.text holds the agent's emitted prose. If absent (older
# runtime), bail silently — no payload, no detection.
RESPONSE=$(printf '%s' "$INPUT" | jq -r '.tool_response.text // .tool_response.output // empty' 2>/dev/null || echo "")
[[ -z "$RESPONSE" ]] && exit 0

SESSION_ID_RAW=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || echo "")
SESSION_ID=$(printf '%s' "$SESSION_ID_RAW" | tr -cd 'A-Za-z0-9_-' | cut -c1-64)
[[ -z "$SESSION_ID" ]] && SESSION_ID="unknown"

STATE_DIR="${ARCA_AUTO_ADR_STATE_DIR:-${HOME}/.claude/state/auto-adr-nudges}"
mkdir -p "$STATE_DIR" 2>/dev/null || exit 0

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-${PWD}}"
STATS_HELPER="${PROJECT_DIR}/hooks/lib/auto-adr-stats.sh"

# ---------------------------------------------------------------------
# Score the response.
# ---------------------------------------------------------------------
score=0

# Lowercase once for case-insensitive matching. Cap at 16KB to bound
# regex CPU on outsized agent outputs.
LOWER=$(printf '%s' "$RESPONSE" | head -c 16384 | tr '[:upper:]' '[:lower:]')

# Helper: count occurrences of an extended regex in $LOWER.
count_matches() {
    printf '%s' "$LOWER" | grep -oE "$1" 2>/dev/null | wc -l
}

# Bare ADR mention NOT followed by -NNN. The first regex catches "adr"
# as a whole word; the second subtracts mentions that are part of an
# existing reference like "adr-003".
adr_total=$(count_matches '\badr\b')
adr_cited=$(count_matches '\badr-[0-9]{3}\b')
adr_bare=$((adr_total - adr_cited))
(( adr_bare > 0 )) && score=$((score + 3))

if printf '%s' "$LOWER" | grep -qE '\b(supersed(e|es|ed)|deprecat(e|es|ed))\b'; then
    score=$((score + 3))
fi

if printf '%s' "$LOWER" | grep -qE '\b(decision|decided|we will use|we chose|chose to)\b'; then
    score=$((score + 2))
fi

if printf '%s' "$LOWER" | grep -qE '\btrade-?offs?\b'; then
    score=$((score + 2))
fi

if printf '%s' "$LOWER" | grep -qE '\b(alternatives?|options? considered|considered options)\b'; then
    score=$((score + 2))
fi

if printf '%s' "$LOWER" | grep -qE '\barchitectur(e|al)\b'; then
    score=$((score + 1))
fi

if printf '%s' "$LOWER" | grep -qE '\b(rationale|justification|because we)\b'; then
    score=$((score + 1))
fi

if printf '%s' "$LOWER" | grep -qE '\b(consequences?|implications?)\b'; then
    score=$((score + 1))
fi

# Anti-trigger: cite of an existing ADR drains 5 points. If the output
# is talking about an ADR that already exists, no new one is needed.
if (( adr_cited > 0 )); then
    score=$((score - 5))
fi

# Anti-trigger: recent ADR file write. Walk docs/adr for any NNN-*.md
# touched in the last 300 seconds. Skipped under test toggle.
if [[ "${ARCA_AUTO_ADR_DISABLE_RECENCY:-}" != "1" ]]; then
    ADR_DIR="${PROJECT_DIR}/docs/adr"
    if [[ -d "$ADR_DIR" ]]; then
        recent_adr=$(find "$ADR_DIR" -maxdepth 1 -type f -name '[0-9][0-9][0-9]-*.md' \
            -newermt "$(date -d '5 minutes ago' '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date '+%Y-%m-%d %H:%M:%S')" \
            2>/dev/null | head -n 1)
        if [[ -n "$recent_adr" ]]; then
            score=$((score - 5))
        fi
    fi
fi

THRESHOLD=4
if (( score < THRESHOLD )); then
    exit 0
fi

# ---------------------------------------------------------------------
# Rate-limit: one nudge per (session, agent) per hour.
# ---------------------------------------------------------------------
MARKER="${STATE_DIR}/${SESSION_ID}-${SUBAGENT}.marker"
NOW_EPOCH=$(date +%s)
WINDOW=3600

if [[ -f "$MARKER" ]]; then
    last=$(cat "$MARKER" 2>/dev/null || echo 0)
    if [[ -n "$last" ]] && (( NOW_EPOCH - last < WINDOW )); then
        bash "$STATS_HELPER" suppressed_dup 2>/dev/null || true
        exit 0
    fi
fi

printf '%s' "$NOW_EPOCH" > "$MARKER"

bash "$STATS_HELPER" detected 2>/dev/null || true

# ---------------------------------------------------------------------
# Emit advisory nudge. stderr so the runtime surfaces it without
# blocking the conversation.
# ---------------------------------------------------------------------
cat >&2 <<EOF
[AUTO-ADR ADVISOR] @architect-ai output looks like an architectural decision (heuristic score=${score}, threshold=${THRESHOLD}).

No new docs/adr/NNN-*.md was written in this turn. ARCA mortal sin #4 ("Arquitectura sin ADR / sin justificacion") applies.

Suggested next step:
  /adr-new <short-title>

The skill numbers the ADR sequentially, drops the Nygard template, and you fill in Context / Decision / Rationale / Consequences before merge.

Bypass (logged): export ARCA_AUTO_ADR_BYPASS=1
EOF

exit 0
