#!/usr/bin/env bash
# claude-process-id — resolve the PID of the ancestor `claude` process so
# hooks and skills that share state can scope it per concurrent session.
#
# Why: the previous single-file justify state (current-justification.json)
# collided when two `claude` processes ran in parallel (e.g. main session
# in one repo + worktree session in another). Latest writer won; the
# other Edit failed the judge. Documented and accepted as Option C —
# this script promotes that to Option B by walking the process tree to
# find the `claude` ancestor and exposing its PID as a stable key.
#
# Why ancestor and not $$: hooks and skill run.sh execute inside child
# shells / subprocesses. Their direct $$ differs but their `claude`
# ancestor is the same — that's the natural scope for per-session state.
#
# Output: a single line with the integer PID on stdout. Empty stdout +
# exit 1 if no `claude` ancestor is found (caller falls back to legacy
# single-file behavior).

set -uo pipefail

pid=$$
seen=0
while [[ -n "$pid" && "$pid" != "0" && "$pid" != "1" && $seen -lt 20 ]]; do
    comm=$(ps -o comm= -p "$pid" 2>/dev/null | tr -d ' ')
    if [[ "$comm" == "claude" ]]; then
        printf '%s' "$pid"
        exit 0
    fi
    pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
    seen=$((seen + 1))
done

# No claude ancestor — caller will use the legacy filename.
exit 1
