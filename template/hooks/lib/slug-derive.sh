#!/usr/bin/env bash
# hooks/lib/slug-derive.sh — shared slug derivation for git remote URLs.
#
# Used by:
#   - hooks/session_start.sh (Section 7, rehydrate nudge)
#   - tests/test_session_start_nudge.sh (behavior tests)
#
# Source it: `source "$REPO_ROOT/hooks/lib/slug-derive.sh"`.

# derive_slug — normalize a git remote URL to "owner-repo" lowercase form.
#
# Handles:
#   - https://github.com/owner/repo
#   - https://github.com/owner/repo.git
#   - git@github.com:owner/repo.git
#   - ssh://git@gitlab.com:2222/group/repo.git
#   - https://gitlab.com/org/team/repo.git (nested -> last two segments)
derive_slug() {
    echo "$1" \
        | sed -E 's|\.git$||' \
        | sed -E 's|^[^:/@]+@[^:]+:([0-9]+/)?||' \
        | sed -E 's|^https?://[^/]+/||' \
        | sed -E 's|^ssh://[^/]+/||' \
        | awk -F/ '{ if (NF>=2) print $(NF-1)"/"$NF; else print $0 }' \
        | tr '/' '-' | tr '[:upper:]' '[:lower:]'
}
