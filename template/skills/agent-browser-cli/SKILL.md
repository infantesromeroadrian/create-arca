---
name: agent-browser-cli
description: >-
  Drive Chrome from any Bash-capable agent via vercel-labs/agent-browser CLI (Apache-2.0,
  Rust binary, Chrome for Testing isolated). Codifies when to use agent-browser vs
  claude-in-chrome MCP, the inline-JS-via-stdin pattern that bypasses mixed-content,
  zoom-to-fit via native CDP keypress, and screenshot-as-proof for visual verification.
  Activate when you need browser automation that must not depend on the operator's
  Chrome session, when claude-in-chrome's extension has disconnected, or when running
  in headless / CI / scheduled context. Backed by ADR-032.
effort: medium
---

# agent-browser CLI — Browser Automation for ARCA

## Why this skill exists

ARCA has two browser-automation backbones. They are NOT interchangeable. This skill
documents which one to reach for.

| Tool | Source-of-truth |
|---|---|
| `claude-in-chrome` MCP | Operator's logged-in Chrome + Anthropic extension |
| `agent-browser` CLI | Standalone Rust binary + dedicated Chrome for Testing |

The wrong choice burns 5+ minutes per disconnect (we proved it twice in the
2026-05-07/08 session before this skill existed).

## Decision matrix — which backbone

Use **`agent-browser`** when ANY of:

- Operator's Chrome is in active use and you don't want to interfere with their tabs.
- The task is scripted / repeatable / will run again as part of CI or a scheduled job.
- You need headless mode (no visible Chrome window).
- `claude-in-chrome` has disconnected and reconnect would cost more than the task itself.
- The task does NOT require interaction with claude.ai-logged-in pages.
- You are inside a subagent without MCP access — `agent-browser` works via plain Bash.

Use **`claude-in-chrome`** when:

- Operator wants to watch the agent click through their own browser visually.
- The task interacts with pages where the operator must be logged in (claude.ai,
  internal SSO, GitHub web with OAuth session).
- You have stable extension state and the MCP-native typed schemas are easier than
  composing CLI invocations.

If unsure → default to `agent-browser`. It is the more robust backbone.

## Install (one-time per host)

**Linux (⟦ host_os ⟧ / Arch / Debian / Fedora)** — no sudo, user-space prefix:

```bash
npm install -g --prefix ~/.local agent-browser   # ~10 MB, deps: node ≥20 only
agent-browser install                            # downloads Chrome 148+ for Testing (~175 MB)
                                                 # cached at ~/.agent-browser/browsers/
```

Requires `~/.local/bin` in `$PATH` (already configured on the ⟦ host_os ⟧ host via `~/.config/fish/conf.d/arca.fish`). If Chrome launch fails with `error while loading shared libraries: ...`, run `agent-browser install --with-deps` — the CLI bootstraps the missing system libs (Debian/Ubuntu) or prints the package names to install via the host package manager (Arch/Fedora).

**macOS** (legacy, pre-⟦ host_os ⟧ migration):

```bash
brew install agent-browser            # 9.9 MB binary, deps: node only
agent-browser install                 # same as Linux flow
```

`npm install -g agent-browser` (root prefix) works when `~/.local` prefix is undesirable, but on shared systems prefer the user-space install — keeps the binary outside `/usr/bin` and clear of OS upgrades.

Verify:

```bash
agent-browser --version               # expect 0.27.0+ (smoke-tested 2026-05-15 on ⟦ host_os ⟧)
```

## Critical pattern — inline JS via `eval --stdin` to bypass mixed-content

`https://` pages cannot `fetch('http://127.0.0.1:...')` even when CORS allows it.
This bites us every time we try to side-load JSON from a local HTTP server. The
robust workaround: inline the JSON into the JS payload, pipe via `eval --stdin`.

```bash
agent-browser open https://excalidraw.com

python3 << 'PY' > /tmp/payload.js
import json
doc = json.load(open('/path/to/diagram.excalidraw'))
# Filter degenerate arrows (width=0, height=0) — see "Excalidraw caveats" below
elements = [
    e for e in doc['elements']
    if not (e.get('type') == 'arrow' and e.get('width', 0) == 0 and e.get('height', 0) == 0)
]
print('const elements =', json.dumps(elements), ';')
print("localStorage.setItem('excalidraw', JSON.stringify(elements));")
print("localStorage.removeItem('excalidraw-state');")
print("localStorage.removeItem('version-files');")
print("({ok: true, count: elements.length})")
PY

agent-browser eval --stdin < /tmp/payload.js
agent-browser eval "location.reload()"
```

The `eval --stdin` accepts payloads in the hundreds of KB. We tested 124 KB
without truncation. For multi-MB payloads, prefer `agent-browser upload` against
a real `<input type=file>` element if the target page exposes one — Excalidraw
does not.

### Excalidraw caveats — degenerate arrows + appState regeneration

Two specific gotchas discovered while smoke-testing this pattern against
`https://excalidraw.com` (2026-05-08 session):

1. **Degenerate arrows poison `Shift+1` zoom-to-fit.** If your `.excalidraw`
   contains arrow elements with `width: 0` and `height: 0` (a common output of
   ad-hoc Python generators that set only `points`), Excalidraw renders them
   as zero-area objects. The bounding box of "all elements" then includes a
   point at infinity, and `Shift+1` computes `zoom = NaN`. The page goes
   blank with a *"Scroll back to content"* hint and `NaN%` zoom. Fix: filter
   them in the inject script before serializing (see snippet above).

2. **Don't set `excalidraw-state` from a partial `appState`.** Excalidraw
   needs ~30 keys in its appState (`zoom`, `scrollX`, `scrollY`,
   `currentItemBackgroundColor`, etc.). Setting only
   `{ viewBackgroundColor: '#ffffff' }` and leaving the rest absent leaves
   internal state in `NaN` for derived values. The robust pattern is to
   `removeItem('excalidraw-state')` and let Excalidraw regenerate the full
   default appState on first load. Same applies to `version-files`.

## Critical pattern — keyboard shortcuts via native CDP

`document.dispatchEvent(new KeyboardEvent(...))` from inside `eval` is often
swallowed by React/Vue listeners that only honor real keystrokes. `agent-browser
press` sends the event through CDP, which Excalidraw, Notion, Linear, and similar
SPAs DO honor.

```bash
agent-browser press 'Shift+1'         # Excalidraw zoom-to-fit (worked here)
agent-browser press 'Control+s'       # Linux save dialog (Mac: 'Cmd+s')
agent-browser press Escape            # close modal
```

`press` translates the key spec to the platform-correct CDP event. Use `Control+*` on Linux / `Cmd+*` on macOS — the underlying Chrome handles both, but writing the platform-native form makes the intent explicit.

When in doubt, prefer `press` over synthesizing keyboard events in `eval`.

## Critical pattern — screenshot as proof of render

After any non-trivial interaction, take a screenshot and `Read` it. PNG-format
screenshots are inline-readable in Claude Code, so visual verification is one
tool call away.

```bash
agent-browser screenshot --full /tmp/proof.png
# then in Claude Code: Read /tmp/proof.png
```

`--full` captures the entire page, not just the viewport. Useful for long forms,
infinite scrolls, and any rendered diagram.

## Common command palette (quick reference)

```bash
# Navigation
agent-browser open <url>                 # alias: goto / navigate
agent-browser close --all                # always cleanup at end of script

# Snapshot — best for LLMs (returns refs @e1, @e2 directly)
agent-browser snapshot                   # accessibility tree
agent-browser screenshot --annotate      # screenshot with numbered labels

# Act by ref or selector
agent-browser click @e3                  # by ref from snapshot
agent-browser click "#submit-btn"        # by CSS selector
agent-browser fill @e2 "text"            # fill by ref
agent-browser find role button click --name "Submit"
agent-browser find label "Email" fill "test@test.com"

# State
agent-browser get text @e5               # innerText
agent-browser get value @e2              # input value
agent-browser get url
agent-browser is visible @e1

# Wait
agent-browser wait <selector>            # element visible
agent-browser wait --text "Welcome"
agent-browser wait --url "**/dashboard"
agent-browser wait --load networkidle

# JS
agent-browser eval "document.title"
agent-browser eval --stdin < payload.js  # for large payloads

# Capture
agent-browser screenshot [path] [--full]
agent-browser pdf /tmp/page.pdf
```

## Anti-patterns

- Do NOT chain `agent-browser open` calls without `agent-browser close --all`
  between sessions — leaks Chrome processes that survive the script.
- Do NOT pipe agent-browser output into `head` / `tail` blindly — the CLI emits
  JSON-or-text mixed; parse with `--json` flag if available, or wrap stdout
  capture explicitly.
- Do NOT use `eval` to dispatch keyboard events to SPA pages — use `press`.
- Do NOT assume `fetch` from a `https://` page can hit `http://localhost` — it
  cannot. Inline the data with `eval --stdin`.
- Do NOT use this skill in scopes that require the operator's authenticated
  Chrome session (claude.ai, logged-in GitHub OAuth) — use `claude-in-chrome`
  instead.

## Coordination with `claude-in-chrome`

These two backbones can coexist in the same session. If you start a task in one
and the other is the right tool, just close the first and open the second. State
is not shared (different Chrome processes, different localStorage, different
cookies) — this is a feature, not a bug.

## Upstream skills (consult before guessing flags)

The CLI ships its own skill catalog version-matched to the binary. When in doubt about the canonical invocation of an obscure command, consult upstream FIRST:

```bash
agent-browser skills get core --full       # full overview + command reference
agent-browser skills list                  # available skill names
agent-browser skills get <name>            # electron, slack, exploratory testing, ...
agent-browser skills path                  # filesystem location of the skill bundles
```

This ARCA SKILL.md captures the *workflow patterns* (when to use which backbone, inline-JS bypass, screenshot-as-proof). The upstream `core` skill captures the *flag-level reference*. They are complementary.

## Smoke test status

- **2026-05-08 macOS** — 437-element ARCA architecture diagram rendered at https://excalidraw.com via 124 KB inline-JS payload. PASS (original commission per ADR-032).
- **2026-05-15 ⟦ host_os ⟧ ⟦ host_machine ⟧** — 5-step smoke (`open https://example.com` → `snapshot` → `screenshot` → `eval "document.title"` → `close --all`) PASS without `--with-deps`. Binary `agent-browser@0.27.0` via `npm install -g --prefix ~/.local`. Chrome 148.0.7778.167 cached at `~/.agent-browser/browsers/`. No shared-library failures.

## Reference

- ADR-032: rationale, scope, smoke-test results.
- Repo: https://github.com/vercel-labs/agent-browser (Apache-2.0)
- Homepage: https://agent-browser.dev
