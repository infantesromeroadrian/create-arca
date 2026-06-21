#!/bin/bash
# ARCA — git-commit-validator stats updater (Task #50 ADV-1)
#
# Increments a counter inside ~/.claude/state/git-commit-validator-stats.json.
# Counter buckets:
#   pass_conventional    — commit message matched conventional regex and passed
#   skip_substitution    — message used $(...) / backtick / ${VAR} expansion → skip
#   skip_heredoc         — message used <<EOF / <<-EOF / <<'EOF' marker → skip
#   skip_non_commit      — bash command was not `git commit -m` → skip
#   skip_amend           — `git commit --amend` without -m → skip
#   skip_no_message      — extractor returned empty MSG (shlex parse failed) → skip
#   block_format         — exit 2: subject did not match conventional regex
#   block_length         — exit 2: subject > 72 chars
#
# Why this exists (telemetry value):
#   Task #50 ADV-1 — the HEREDOC skip path is a fail-safe, not a fail-block.
#   If `skip_substitution` or `skip_heredoc` grow unbounded vs `pass_conventional`,
#   operators are leaning on the escape hatch instead of writing conventional
#   commits. The metric makes that drift observable so a future heuristic
#   (post-commit hook re-validating the expanded message via git log) can be
#   justified with data, not vibes.
#
# Pattern lifted from hooks/lib/auto-adr-stats.sh:
#   - idempotent
#   - silent (no stdout/stderr in the hot path)
#   - fail-open (missing jq, missing dir, etc. → exit 0, never blocks the commit)
#   - flock-guarded against concurrent invocations

set -uo pipefail

bucket="${1:-unknown}"
STATS_FILE="${HOME}/.claude/state/git-commit-validator-stats.json"

command -v jq >/dev/null 2>&1 || exit 0

STATE_DIR="$(dirname "$STATS_FILE")"
mkdir -p "$STATE_DIR" 2>/dev/null || exit 0

# Writability gate. Bash evaluates redirection targets BEFORE applying any
# 2>/dev/null on the same line, so a read-only state dir would emit
# "Permission denied" to stderr before the trailing redirect could swallow
# it — and that stderr flows up to the Claude Code UI through the calling
# hook. Test the dir once up-front and exit silently if we can't write.
# Telemetry is fail-open by design (the metric is observability, not policy).
[[ -w "$STATE_DIR" ]] || exit 0
if [[ -f "$STATS_FILE" && ! -w "$STATS_FILE" ]]; then
    exit 0
fi

if [[ ! -f "$STATS_FILE" ]]; then
    cat > "$STATS_FILE" <<'EOF'
{
  "pass_conventional": 0,
  "skip_substitution": 0,
  "skip_heredoc": 0,
  "skip_non_commit": 0,
  "skip_amend": 0,
  "skip_no_message": 0,
  "block_format": 0,
  "block_length": 0,
  "first_seen": null,
  "last_updated": null
}
EOF
fi

now="$(date -Iseconds)"
tmp="${STATS_FILE}.tmp.$$"
LOCK_FILE="${STATS_FILE}.lock"

{
    flock -x 9
    jq --arg b "$bucket" --arg now "$now" '
        .[$b] = (.[$b] // 0) + 1
        | .first_seen = (.first_seen // $now)
        | .last_updated = $now
    ' "$STATS_FILE" > "$tmp" 2>/dev/null

    if [[ -s "$tmp" ]]; then
        mv "$tmp" "$STATS_FILE"
    else
        rm -f "$tmp"
    fi
} 9>"$LOCK_FILE"

exit 0
