#!/bin/bash
# ARCA — MCP frontmatter parity hook (PreToolUse:Edit / Write / MultiEdit).
#
# Closes the gap that ADR-031 surfaced: agent .md files can declare
# mcp__X__* tools in their `tools:` frontmatter while the X server is
# never registered in any of the 4 Claude Code config tiers
# (<repo>/settings.json, <repo>/.mcp.json, ~/.claude/settings.json,
# ~/.claude.json).  The agent silently fails at runtime — the operator
# has no warning until they actually invoke the tool.
#
# Trigger: any Edit/Write/MultiEdit on agents/*.md or on a config file
# that could un-register an MCP (settings.json, .mcp.json,
# ~/.claude/settings.json, ~/.claude.json).
#
# Behaviour:
#   - Compute set R = MCPs referenced via mcp__X__ in any agents/*.md
#     frontmatter `tools:` line.
#   - Compute set S = MCPs registered in the 4 tiers (union).
#   - If the file being edited is an agent .md, also include the NEW
#     content of the frontmatter being written, not just the on-disk one.
#   - Drift = R - S.  If non-empty, exit 2 with stderr explaining which
#     agent declares which orphan MCP, and which tier should register it.
#   - Bypass: ARCA_PARITY_BYPASS=1 (audit-logged).
#
# Fail-open on parser errors so a malformed frontmatter doesn't lock the
# operator out of editing the very file that needs fixing.

set -uo pipefail

# Resolve repo root from ARCA_REPO_ROOT (falls back to ARCA_REPO, then to the
# canonical A.R.C.A/ location if both are unset or stale — e.g. inherited from a
# terminal opened before the repos were grouped under A.R.C.A/, 2026-06-14).
REPO_ROOT="${ARCA_REPO_ROOT:-${ARCA_REPO:-${HOME}/Desktop/⟦ host_alias ⟧/A.R.C.A/.claude}}"
[[ -d "$REPO_ROOT" ]] || REPO_ROOT="${HOME}/Desktop/⟦ host_alias ⟧/A.R.C.A/.claude"
LOG_DIR="${HOME}/.claude/state"
LOG="${LOG_DIR}/mcp-frontmatter-parity.log"
mkdir -p "$LOG_DIR" 2>/dev/null || true

# Bypass — audit logged
if [[ "${ARCA_PARITY_BYPASS:-0}" == "1" ]]; then
    echo "$(date -Iseconds) | bypassed via ARCA_PARITY_BYPASS=1" >> "$LOG"
    exit 0
fi

# Read hook payload from stdin (Claude Code passes JSON)
PAYLOAD="$(cat 2>/dev/null || echo '{}')"

# Extract the file path being edited (best-effort across tool shapes)
FILE_PATH="$(echo "$PAYLOAD" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
    ti = d.get("tool_input", {})
    print(ti.get("file_path", "") or ti.get("filePath", "") or "")
except Exception:
    print("")
' 2>/dev/null)"

# Only enforce when the edited path is in scope: agents/*.md or known config tiers
case "$FILE_PATH" in
    */agents/*.md|*/.mcp.json|*/.claude/settings.json|*/.claude.json|*/settings.json)
        ;;
    *)
        # not in scope — let it through silently
        exit 0
        ;;
esac

# Compute parity inside Python for robustness
DRIFT_REPORT="$(REPO_ROOT="$REPO_ROOT" FILE_PATH="$FILE_PATH" PAYLOAD_JSON="$PAYLOAD" python3 - <<'PY'
import os, re, json, sys

REPO_ROOT = os.environ["REPO_ROOT"]
FILE_PATH = os.environ["FILE_PATH"]

def load_mcps(path):
    try:
        with open(path) as f:
            d = json.load(f)
        return set(d.get("mcpServers", {}).keys())
    except (FileNotFoundError, json.JSONDecodeError):
        return set()

# 4 config tiers
registered = (
    load_mcps(os.path.join(REPO_ROOT, "settings.json"))
    | load_mcps(os.path.join(REPO_ROOT, ".mcp.json"))
    | load_mcps(os.path.expanduser("~/.claude/settings.json"))
    | load_mcps(os.path.expanduser("~/.claude.json"))
)

# Scan all agents/*.md for mcp__X__ in frontmatter `tools:` line
agents_dir = os.path.join(REPO_ROOT, "agents")
referenced_by = {}   # mcp_name -> [list of agents]

def extract_tools_block(content):
    m = re.match(r"^---\n(.*?)\n---", content, re.DOTALL)
    if not m:
        return ""
    fm = m.group(1)
    tools_match = re.search(r"^tools:\s*(.*?)(?=\n[a-z][a-z0-9_-]*:|\Z)", fm, re.MULTILINE | re.DOTALL)
    return tools_match.group(1) if tools_match else ""

if os.path.isdir(agents_dir):
    for fname in sorted(os.listdir(agents_dir)):
        if not fname.endswith(".md"):
            continue
        path = os.path.join(agents_dir, fname)
        try:
            with open(path) as f:
                content = f.read()
        except OSError:
            continue
        # If we're editing this agent right now, prefer the NEW content
        # from the payload — but only when payload provides a complete
        # write (Write tool) or new_string covers the frontmatter
        # (Edit tool with frontmatter region).  We approximate by checking
        # if the FILE_PATH matches and the payload has tool_input.content
        # (Write) — Edit's new_string is partial and harder to merge.
        if FILE_PATH == path:
            try:
                payload = json.loads(os.environ.get("PAYLOAD_JSON", "{}"))
                ti = payload.get("tool_input", {})
                full = ti.get("content")
                if full and full.startswith("---"):
                    content = full
            except Exception:
                pass
        tools = extract_tools_block(content)
        for ref in re.findall(r"mcp__([a-zA-Z0-9_-]+)__", tools):
            referenced_by.setdefault(ref, []).append(fname.replace(".md", ""))

drift = {mcp: sorted(set(agents)) for mcp, agents in referenced_by.items() if mcp not in registered}
if not drift:
    print("OK")
else:
    print("DRIFT")
    for mcp, agents in sorted(drift.items()):
        print(f"  mcp__{mcp}__* declared by: {', '.join(agents)}")
        print(f"    Not registered in any of the 4 tiers — runtime calls will silently fail.")
PY
)"

if [[ "$DRIFT_REPORT" == "OK" ]]; then
    exit 0
fi

# Fail-open: if the python parity computation produced no usable verdict
# (python3 missing, interpreter error, empty output), do NOT block the
# operator — warn to stderr and let the edit through. A parser failure
# must never lock the operator out of fixing the very file at fault.
if [[ "$DRIFT_REPORT" != DRIFT* ]]; then
    echo "[mcp-frontmatter-parity] WARN: parity check produced no verdict (python3 missing or parser error) — failing open." >&2
    echo "$(date -Iseconds) | FAIL-OPEN (no verdict) on $FILE_PATH" >> "$LOG"
    exit 0
fi

# Drift detected → exit 2 with actionable stderr
{
    echo ""
    echo "=========================================================================="
    echo "[mcp-frontmatter-parity] BLOCKED — agent frontmatter references unregistered MCP"
    echo "=========================================================================="
    echo "$DRIFT_REPORT"
    echo ""
    echo "Fix one of:"
    echo "  - Register the MCP in the appropriate tier (claude mcp add ...)"
    echo "  - Remove the mcp__X__* tool entries from the agent's frontmatter"
    echo ""
    echo "Bypass for emergencies (audit-logged):"
    echo "  ARCA_PARITY_BYPASS=1"
    echo "=========================================================================="
} >&2

echo "$(date -Iseconds) | DRIFT block on $FILE_PATH" >> "$LOG"
exit 2
