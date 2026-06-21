#!/bin/bash

export PATH="$HOME/go/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"  # ARCA: ensure engram + brew binaries discoverable
set -uo pipefail

# SessionStart hook — ARCA intelligent startup
# Shows: banner + briefing + git context + Engram + project phase detection

# Cross-platform sha256 (Linux coreutils `sha256sum` vs macOS/BSD `shasum -a 256`).
_ares_sha256() {
    if command -v sha256sum >/dev/null 2>&1; then
        printf '%s' "$1" | sha256sum | cut -c1-12
    elif command -v shasum >/dev/null 2>&1; then
        printf '%s' "$1" | shasum -a 256 | cut -c1-12
    else
        # Last-resort fallback: sanitize to a-z0-9, truncate 12 chars.
        printf '%s' "$1" | tr -cd 'a-z0-9' | cut -c1-12
    fi
}

STATE_DIR="${HOME}/.claude/state"
BRIEFING_DIR="${HOME}/.claude/briefing"
SESSION_LOG="${HOME}/.claude/session-log.txt"

mkdir -p "$STATE_DIR" "$BRIEFING_DIR"

# Log session start
echo "$(date -Iseconds) session_start cwd=$(pwd)" >> "$SESSION_LOG"

# Save last session timestamp for delta calculations
LAST_SESSION=""
if [ -f "$STATE_DIR/last_session_ts" ]; then
    LAST_SESSION=$(cat "$STATE_DIR/last_session_ts")
fi
date -Iseconds > "$STATE_DIR/last_session_ts"

# Count ecosystem components
AGENTS=$(find "${HOME}/.claude/agents" -name "*.md" 2>/dev/null | wc -l)
SKILLS=$(find "${HOME}/.claude/skills" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
COMMANDS=$(find "${HOME}/.claude/commands" -name "*.md" 2>/dev/null | wc -l)
HOOKS=$(find "${HOME}/.claude/hooks" -name "*.sh" 2>/dev/null | wc -l)

DIM="\033[38;2;100;110;120m"
CYAN="\033[38;2;78;205;196m"
BLUE="\033[38;2;88;166;255m"
YELLOW="\033[38;2;255;214;102m"
RESET="\033[0m"

{
    echo -e "    ${CYAN}ARCA${RESET} ${DIM}·${RESET} ${BLUE}Opus 4.8 · Sonnet 4.6 · Haiku 4.5${RESET} ${DIM}·${RESET} ${AGENTS}a/${SKILLS}s/${COMMANDS}c/${HOOKS}h"
    echo ""

    # --- Section 1: Daily Briefing ---
    # Check local briefing first, then repo briefing (from remote scheduled agent)
    BRIEFING_FILE=""
    TODAY=$(date +%Y-%m-%d)

    # Priority 1: local briefing
    if [ -f "${BRIEFING_DIR}/latest.md" ]; then
        LOCAL_DATE=$(date -r "${BRIEFING_DIR}/latest.md" +%Y-%m-%d 2>/dev/null || echo "")
        if [ "$LOCAL_DATE" = "$TODAY" ]; then
            BRIEFING_FILE="${BRIEFING_DIR}/latest.md"
        fi
    fi

    # Priority 2: repo briefing (committed by remote scheduled agent)
    if [ -z "$BRIEFING_FILE" ] && git rev-parse --is-inside-work-tree &>/dev/null; then
        # Quick fetch to check for new briefings (non-blocking, 3s timeout)
        timeout 3 git fetch origin main --quiet 2>/dev/null || true
        REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
        REPO_BRIEFING="${REPO_ROOT}/briefings/latest.md"
        if [ -f "$REPO_BRIEFING" ]; then
            REPO_DATE=$(head -1 "$REPO_BRIEFING" | grep -oP '\d{4}-\d{2}-\d{2}' || echo "")
            if [ "$REPO_DATE" = "$TODAY" ]; then
                BRIEFING_FILE="$REPO_BRIEFING"
                # Cache locally for faster next access
                cp "$REPO_BRIEFING" "${BRIEFING_DIR}/latest.md" 2>/dev/null || true
            fi
        fi
    fi

    if [ -n "$BRIEFING_FILE" ]; then
        HEADLINE=$(head -1 "$BRIEFING_FILE" | sed 's/^#\+ *//')
        echo -e "    ${YELLOW}[BRIEFING]${RESET} ${HEADLINE}"
        grep -v '^#\|^$\|^---' "$BRIEFING_FILE" | head -5 | sed "s/^/    /" || true
        echo ""
    fi

    # --- Section 2: Git context (what changed since last session) ---
    if git rev-parse --is-inside-work-tree &>/dev/null; then
        PROJECT=$(basename "$(git rev-parse --show-toplevel)")
        BRANCH=$(git branch --show-current 2>/dev/null || echo "detached")

        # Commits since last session
        if [ -n "$LAST_SESSION" ]; then
            RECENT_COMMITS=$(git log --oneline --since="$LAST_SESSION" 2>/dev/null | head -5)
            COMMIT_COUNT=$(git log --oneline --since="$LAST_SESSION" 2>/dev/null | wc -l)
        else
            RECENT_COMMITS=$(git log --oneline -3 2>/dev/null)
            COMMIT_COUNT="?"
        fi

        # Uncommitted changes
        DIRTY=$(git status --porcelain 2>/dev/null | wc -l)
        STAGED=$(git diff --cached --name-only 2>/dev/null | wc -l)

        echo -e "    ${YELLOW}[PROYECTO]${RESET} ${PROJECT} (${BRANCH})"
        if [ "$DIRTY" -gt 0 ]; then
            echo -e "    ${DIM}${DIRTY} archivos modificados, ${STAGED} staged${RESET}"
        fi
        if [ -n "$RECENT_COMMITS" ]; then
            if [ -n "$LAST_SESSION" ]; then
                echo -e "    ${DIM}${COMMIT_COUNT} commits desde ultima sesion:${RESET}"
            else
                echo -e "    ${DIM}Ultimos commits:${RESET}"
            fi
            while IFS= read -r line; do
                echo -e "    ${DIM}  ${line}${RESET}"
            done <<< "$RECENT_COMMITS"
        fi
        echo ""
    fi

    # --- Section 3: Pipeline phase detection ---
    # Check if current project has an active ML pipeline by looking for phase markers
    if [ -d "docs/adr" ] || [ -f "AGENTS.md" ]; then
        # Check for phase artifacts
        PHASE="unknown"
        if [ -d "monitoring" ] || [ -d "dashboards" ]; then
            PHASE="F7 (Monitoring)"
        elif [ -f "Dockerfile" ] || [ -d "deploy" ]; then
            PHASE="F6 (Deploy)"
        elif [ -d "tests" ] && [ -f "tests/test_*.py" ] 2>/dev/null; then
            PHASE="F5 (Quality)"
        elif [ -d "src" ] || [ -d "models" ]; then
            PHASE="F4 (Build)"
        elif [ -d "docs/adr" ]; then
            PHASE="F3 (Design)"
        fi
        if [ "$PHASE" != "unknown" ]; then
            echo -e "    ${YELLOW}[FASE]${RESET} ${PHASE}"
            echo ""
        fi
    fi

    # --- Section 4: Engram context (last session memories) ---
    if command -v engram &>/dev/null; then
        CONTEXT=$(engram context 2>/dev/null | head -8)
        if [ -n "$CONTEXT" ]; then
            echo -e "    ${YELLOW}[MEMORIA]${RESET}"
            while IFS= read -r line; do
                echo -e "    \033[38;2;100;110;120m${line}\033[0m"
            done <<< "$(echo "$CONTEXT" | head -5)"
            echo ""
        fi
    fi

    # --- Section 5: Pending alerts ---
    # Check telemetry for errors in last 24h
    TELEMETRY="${HOME}/.claude/telemetry.jsonl"
    if [ -f "$TELEMETRY" ]; then
        ERRORS_24H=$(awk -v cutoff="$(date -d '24 hours ago' -Iseconds 2>/dev/null || date -v-24H -Iseconds 2>/dev/null || echo '')" \
            '$0 ~ /"type":"error"/ && $0 > cutoff' "$TELEMETRY" 2>/dev/null | wc -l)
        if [ "$ERRORS_24H" -gt 0 ]; then
            echo -e "    ${YELLOW}[ALERTA]${RESET} ${ERRORS_24H} errores en ultimas 24h"
            echo ""
        fi
    fi

    # --- Section 6: Auto-tuning pending (from critic feedback tracker) ---
    CRITIC_FILE="${STATE_DIR}/critic_rejections.json"
    if [ -f "$CRITIC_FILE" ]; then
        PENDING=$(jq -r '.auto_tune_pending | length' "$CRITIC_FILE" 2>/dev/null)
        if [ "$PENDING" -gt 0 ]; then
            AGENTS_LIST=$(jq -r '.auto_tune_pending | join(", ")' "$CRITIC_FILE" 2>/dev/null)
            echo -e "    ${YELLOW}[AUTO-TUNE]${RESET} ${PENDING} agentes pendientes de optimizacion: ${AGENTS_LIST}"
            echo -e "    ${DIM}Ejecuta: @prompt-engineer para revisar sus prompts${RESET}"
            echo ""
        fi
    fi

    # --- Section 7: Engram rehydrate nudge (Track B Fila 3) ---
    # Suggest `/rehydrate` when the memory/ directory is stale or empty,
    # so Claude's native Memory tool loads fresh Engram context.
    if [ ! -f "${HOME}/.claude/memory-rehydrate-off" ] && command -v engram >/dev/null 2>&1; then
        if git rev-parse --is-inside-work-tree &>/dev/null; then
            _origin=$(git remote get-url origin 2>/dev/null || echo "")
            if [ -n "$_origin" ]; then
                # Slug derivation extracted to hooks/lib/slug-derive.sh so the
                # behavior tests in tests/test_session_start_nudge.sh exercise
                # the same code path instead of a duplicated copy.
                # shellcheck source=lib/slug-derive.sh
                . "$(dirname "${BASH_SOURCE[0]}")/lib/slug-derive.sh"
                _slug=$(derive_slug "$_origin")
                # Sanitize: reject path traversal or illegal chars, fall back to cwd-hash.
                if echo "$_slug" | grep -qE '^[a-z0-9-]{1,80}$'; then
                    :
                else
                    _slug=$(_ares_sha256 "$(pwd)")
                fi
            else
                _slug=$(basename "$(pwd)" | tr '[:upper:]' '[:lower:]')
                if ! echo "$_slug" | grep -qE '^[a-z0-9-]{1,80}$'; then
                    _slug=$(_ares_sha256 "$(pwd)")
                fi
            fi
            _mem_dir="${HOME}/.claude/memory/${_slug}"
            _mem_readme="${_mem_dir}/README.md"
            _nudge=""
            if [ ! -f "$_mem_readme" ]; then
                _nudge="memory/${_slug}/ vacio"
            else
                # Stale if README older than 24h.
                _age_sec=$(( $(date +%s) - $(stat -c %Y "$_mem_readme" 2>/dev/null || echo 0) ))
                if [ "$_age_sec" -gt 86400 ]; then
                    _nudge="memory/${_slug}/ stale (>24h)"
                fi
            fi
            if [ -n "$_nudge" ]; then
                echo -e "    ${YELLOW}[MEMORY]${RESET} ${_nudge}"
                echo -e "    ${DIM}Ejecuta: /rehydrate para materializar Engram top-K${RESET}"
                echo ""
            fi
            unset _origin _slug _mem_dir _mem_readme _nudge _age_sec
        fi
    fi

} > /dev/tty 2>/dev/null || true

# Output additionalContext for Claude
PROJECT_NAME=""
BRANCH_NAME=""
UNCOMMITTED=0
AUTO_TUNE=""
if git rev-parse --is-inside-work-tree &>/dev/null; then
    PROJECT_NAME=$(basename "$(git rev-parse --show-toplevel)")
    BRANCH_NAME=$(git branch --show-current 2>/dev/null || echo "detached")
    UNCOMMITTED=$(git status --porcelain 2>/dev/null | wc -l)
fi

CRITIC_FILE="${STATE_DIR}/critic_rejections.json"
if [ -f "$CRITIC_FILE" ]; then
    PENDING_AGENTS=$(jq -r '.auto_tune_pending | join(", ")' "$CRITIC_FILE" 2>/dev/null)
    if [ -n "$PENDING_AGENTS" ] && [ "$PENDING_AGENTS" != "" ]; then
        AUTO_TUNE="Auto-tune pending: ${PENDING_AGENTS}"
    fi
fi

# --- ADR-103: project-start orchestration nudge ----------------------------
# At project open, if ARCA has NO prior memory for this project's slug (signal
# (b): "never oriented here before"), suggest opening with orchestration. Soft,
# once-per-project (slug-keyed marker), fail-open (exit 0 always). Reuses the
# same slug-derive.sh as §7 — no second classifier. Suggests COMMANDS ⟦ user_name ⟧
# runs (never @team-composer, a phantom agent — invoking it fails). The per-
# project half of the orchestration-discipline symptom; ADR-102 covers per-task.
PROJECT_START_NUDGE=""
if [ "${ARCA_PROJECT_START_NUDGE_DISABLE:-0}" != "1" ] && git rev-parse --is-inside-work-tree &>/dev/null; then
    _ps_origin=$(git remote get-url origin 2>/dev/null || echo "")
    _ps_root=$(git rev-parse --show-toplevel 2>/dev/null || echo ".")
    if [ -n "$_ps_origin" ] && [ -r "$(dirname "${BASH_SOURCE[0]}")/lib/slug-derive.sh" ]; then
        # shellcheck source=lib/slug-derive.sh
        . "$(dirname "${BASH_SOURCE[0]}")/lib/slug-derive.sh"
        _ps_slug=$(derive_slug "$_ps_origin" 2>/dev/null || echo "")
        if echo "$_ps_slug" | grep -qE '^[a-z0-9-]{1,80}$'; then
            _ps_readme="${HOME}/.claude/memory/${_ps_slug}/README.md"
            _ps_marker_dir="${STATE_DIR}/project-start-nudged"
            _ps_marker="${_ps_marker_dir}/${_ps_slug}"
            # Signal (b)∧(a): no prior ARCA memory for the slug AND no own
            # docs/adr/ — AND not already nudged (once-per-project). The AND
            # with (a) resolves ADR-103 §5.1 toward (b)∧(a), NOT the ADR's
            # tentative (b)-alone default: verified on host 2026-06-11 that
            # ~/.claude/memory/ is unpopulated (memories live in Engram, only
            # materialized to <slug>/README.md when /rehydrate runs), so (b)
            # alone fires on EVERY repo including established ones. docs/adr/
            # presence is the proxy for "an established project ARCA knows".
            if [ ! -f "$_ps_readme" ] && [ ! -d "${_ps_root}/docs/adr" ] && [ ! -f "$_ps_marker" ]; then
                PROJECT_START_NUDGE="New project detected (no prior ARCA memory for '${_ps_slug}'). If this is real work, consider opening with an orchestration plan: /orchestrate for a bespoke agent DAG, or /ml-new / /rag-new / /spec-new for a fixed pipeline. Soft nudge — ignore if exploratory."
                # Stamp the SLUG-keyed marker (NOT session-keyed) so it fires at
                # most once per project (ADR-103 §5.2 — the load-bearing detail).
                mkdir -p "$_ps_marker_dir" 2>/dev/null && : > "$_ps_marker" 2>/dev/null || true
                # Telemetry into the SF-1 sink, fail-open.
                _ps_telem="${ARCA_REFLEX_TELEMETRY:-${STATE_DIR}/reflex-telemetry.jsonl}"
                if command -v jq >/dev/null 2>&1; then
                    _ps_ts=$(date -Iseconds 2>/dev/null || echo "")
                    jq -nc --arg ts "$_ps_ts" --arg slug "$_ps_slug" \
                        '{ts:$ts, decision:"project_nudge_fired", reason:"no_memory_slug", slug:$slug, source:"session_start"}' \
                        >> "$_ps_telem" 2>/dev/null || true
                    unset _ps_ts
                fi
                unset _ps_telem
            fi
            unset _ps_readme _ps_marker_dir _ps_marker
        fi
        unset _ps_slug
    fi
    unset _ps_origin _ps_root
fi

cat <<CONTEXT
Project: ${PROJECT_NAME:-none} | Branch: ${BRANCH_NAME:-none} | Uncommitted: ${UNCOMMITTED}
${AUTO_TUNE}
${PROJECT_START_NUDGE}
CONTEXT

exit 0
