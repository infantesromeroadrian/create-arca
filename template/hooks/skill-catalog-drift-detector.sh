#!/bin/bash
# ARCA — skill catalog drift detector (PostToolUse:Edit|Write|MultiEdit)
#
# ⟦ user_name ⟧'s `docs/SKILLS.md` and `skills/SKILL_INDEX.json` are auto-generated
# from each skill's `SKILL.md` frontmatter via:
#   1. scripts/build-skill-index.sh   (rebuilds SKILL_INDEX.json)
#   2. scripts/regen-skills-doc.sh    (renders SKILLS.md from index)
#
# When Claude edits a SKILL.md frontmatter (description, model, tier...)
# the two derived files drift. ADR-022 catalog drift gate fires on CI:
#
#   [regen-skills-doc] DRIFT — docs/SKILLS.md does not match SKILL_INDEX.json
#   Process completed with exit code 1.
#
# This blocks merge until both regen scripts run. ⟦ user_name ⟧ got hit by this
# in the 2026-05-03 sweep (Block A → CI fail → manual regen + extra commit).
# This hook closes the latency window: warn at edit time so the regen
# happens before commit, not after CI fail.
#
# Scope (ARCA-specific):
#   Only fires when the active project is .claude. SKILL.md
#   files in other projects (Kaggle, HTB, ⟦ org_name ⟧, personal) maintain their
#   own catalogs.
#
# Behavior:
#   - PostToolUse hook: never blocks (exit 0 always).
#   - Stderr lines are surfaced by the runtime; Claude (and ⟦ user_name ⟧) see
#     them immediately and can run the regen scripts.
#   - No-op if file_path is not under skills/<name>/SKILL.md.
#   - No-op if regen scripts are missing — first-time setup is not drift.
#   - No-op if --check passes (catalog already in sync — frontmatter
#     edits that don't change the indexed fields don't trigger drift).

set -uo pipefail

# Mandatory dependency. Bail silently if absent.
command -v jq >/dev/null 2>&1 || exit 0

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-${PWD}}"
INDEX_BUILDER="${PROJECT_DIR}/scripts/build-skill-index.sh"
DOC_REGEN="${PROJECT_DIR}/scripts/regen-skills-doc.sh"

INPUT=$(cat)
file_path=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || echo "")
[[ -z "$file_path" ]] && exit 0

abs_path=$(realpath -m "$file_path" 2>/dev/null || echo "$file_path")

# Only fire on writes to a SKILL.md inside skills/<name>/.
# Pattern: <project>/skills/<skill-name>/SKILL.md (case-sensitive).
if [[ "$abs_path" != "${PROJECT_DIR}/skills/"*"/SKILL.md" ]]; then
    exit 0
fi

# Scope guard — only enforce the catalog invariant in .claude.
# Same fast-to-slow detection as claude-md-sync-detector.sh.
is_ares_project="false"
if [[ "$(basename "$PROJECT_DIR")" == ".claude" ]]; then
    is_ares_project="true"
elif command -v git >/dev/null 2>&1; then
    remote_url=$(git -C "$PROJECT_DIR" config --get remote.origin.url 2>/dev/null || echo "")
    if [[ "$remote_url" == *".claude"* ]]; then
        is_ares_project="true"
    fi
fi
[[ "$is_ares_project" != "true" ]] && exit 0

# Regen scripts must exist. If missing we're either in first-time setup
# or the repo is incomplete — nothing to warn about.
[[ ! -x "$INDEX_BUILDER" ]] && exit 0
[[ ! -x "$DOC_REGEN" ]] && exit 0

# Run the doc regen check (it compares SKILLS.md against current
# SKILL_INDEX.json). If --check exits 0 the catalog is in sync.
if "$DOC_REGEN" --check >/dev/null 2>&1; then
    exit 0
fi

# Drift detected. Print the exact 2-step regen command ⟦ user_name ⟧ needs.
# Order matters: rebuild index FIRST (it picks up new descriptions),
# then regenerate doc FROM the new index.
skill_name=$(basename "$(dirname "$abs_path")")
{
    echo "[skill-catalog-drift] DRIFT detected after editing skills/${skill_name}/SKILL.md."
    echo "  docs/SKILLS.md no longer matches the SKILL_INDEX (or the SKILL.md frontmatter)."
    echo "  Run BOTH regen scripts in order before commit (CI ADR-022 gate will block otherwise):"
    echo "    bash scripts/build-skill-index.sh && bash scripts/regen-skills-doc.sh"
} >&2

exit 0
