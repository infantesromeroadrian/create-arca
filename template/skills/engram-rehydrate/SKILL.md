---
name: engram-rehydrate
description: Bridge Engram MCP (semantic long-term memory) → Claude Memory Tool directory (filesystem-based native protocol). Queries Engram for top-K relevant memories about the current project, writes them as individual .md files into ~/.claude/memory/<project-slug>/ so Claude can discover them via the native Memory tool's progressive disclosure. Closes the gap between Engram's semantic search and Anthropic's native memory primitive. Track B Feature #3.
paths:
  - "**/.claude/memory/**"
  - "**/memory-rehydrate/**"
effort: medium
---

# ENGRAM-REHYDRATE — semantic memory meets native memory tool

Anthropic's Memory tool expects a plain filesystem directory. Engram
holds semantic embeddings cross-sessions. Both are useful, neither covers
the other. This skill materializes Engram's top-K into the Memory tool's
directory format at session start (or on demand), giving Claude the best
of both: rich semantic recall (via Engram MCP during runtime) PLUS native
memory files that load automatically before the first user prompt.

---

## WHEN TO INVOKE

- Start of a new session on a known project — rehydrate state.
- User says: "refresca la memoria", "rehydrate", "carga contexto de este proyecto".
- `hooks/session_start.sh` detected memory/ is older than 24h or empty (nudge).

## WHEN NOT TO INVOKE

- Same session, already rehydrated → no-op.
- Project has < 3 Engram entries → not worth the overhead, skip.
- User explicitly disabled with `~/.claude/memory-rehydrate-off`.

---

## TARGET DIRECTORY STRUCTURE

```
~/.claude/memory/<project-slug>/
├── README.md                 # index — 1-line per file, generated
├── 001-<topic-slug>.md       # top-1 Engram entry
├── 002-<topic-slug>.md       # top-2
└── ...                       # up to top-K (default 10)
```

`<project-slug>` derives from:
- `git remote get-url origin` if present → owner/repo kebab-case
- else `basename $(pwd)` lowercased

---

## PROTOCOL

### Phase 1 — Detect project + existing state

1. Compute project slug from git remote or cwd.
2. Check if `~/.claude/memory/<project-slug>/` exists.
3. If README.md there has timestamp <24h → skip (already fresh).
4. If `~/.claude/memory-rehydrate-off` exists → skip with quiet log.

### Phase 2 — Engram query plan

Use `engram` MCP (not the limited `search` CLI). Queries in order:

1. `mem_context(last_n=5)` — most recent session context entries.
   NOTE: `mem_context` is not project-scoped by default. Post-filter the
   results by checking each entry's `project` field and discarding any
   whose project differs from the current slug (prevents cross-project
   pollution when the user works on multiple repos).
2. `mem_search(query=<project-slug>, limit=10, scope="project")` — semantic top matches on the project.
3. `mem_timeline(project=<slug>, days=30)` — decision/bugfix entries from last 30 days.

Deduplicate by memory `id`. Keep top K=10 (configurable via `~/.claude/memory-rehydrate-config.json` → `top_k`).

### Phase 3 — Materialization

For each memory entry:

1. Derive a kebab-case slug from the title (truncate to 40 chars).
2. File name: `<NNN>-<slug>.md` where `NNN` is rank zero-padded.
3. Content:
   ```markdown
   ---
   engram_id: <id>
   engram_type: decision|discovery|bugfix|architecture|...
   rank: <NNN>
   rehydrated_at: <iso-8601>
   project: <project-slug>
   ---

   # <title>

   ## What
   <the "What" field from Engram entry>

   ## Why
   <the "Why" field>

   ## How to apply
   <the "How to apply" field if present>
   ```
4. Write atomically (temp file + rename) to avoid partial reads.

### Phase 4 — Index

Write/overwrite `README.md`:

```markdown
---
rehydrated_at: <iso-8601>
source: engram
project: <project-slug>
count: <K>
---

# Memory Index — <project-slug>

Last rehydrated: <iso-8601>
Top <K> Engram entries materialized into Memory tool directory.

| # | Type | Title | Engram ID |
|---|---|---|---|
| 001 | decision | ... | 5 |
| 002 | discovery | ... | 12 |
```

### Phase 5 — Cleanup

Before writing new files, **remove** any pre-existing `.md` files in the
directory that match ALL of the following:

1. Filename matches `^[0-9]{3}-.+\.md$` pattern.
2. Frontmatter parses as valid YAML.
3. Parsed frontmatter has key `source` with value exactly `"engram"`.

**Fallback on ambiguity:** if frontmatter fails to parse (malformed YAML,
truncated file from a prior crash, missing `---` terminators) → **SKIP
the file, never delete it**. Log a warning naming the file. Ambiguous
cleanup is worse than stale data — the user may have partially edited.

Never touch files without the `source: engram` marker (user notes).

### Phase 6 — Confirmation

Report to user:
```
Rehydrated <K> memories from Engram → ~/.claude/memory/<project-slug>/
Top 3: <title1>, <title2>, <title3>
```

If K == 0 (empty Engram for this project):
```
Engram is empty for project <slug>. Nothing to rehydrate. Save context
during the session with `mem_save` to build it up.
```

---

## CONFIG

Location: `~/.claude/memory-rehydrate-config.json` (optional).

```json
{
  "top_k": 10,
  "max_age_hours": 24,
  "include_types": ["decision", "discovery", "bugfix", "architecture"],
  "exclude_scopes": ["personal", "credential"],
  "queries": [
    "project-name",
    "current-phase-topic"
  ]
}
```

If absent, apply defaults embedded above.

---

## ANTI-PATTERNS

- Do NOT write files without the `source: engram` marker — the cleanup
  phase depends on it to know what to overwrite.
- Do NOT query Engram mid-session just to refresh memory/ — use Engram
  MCP directly via `mem_search` or `mem_context` for runtime recall.
  This skill is session-boundary only.
- Do NOT rehydrate on every tool use — check `max_age_hours` and skip.
- Do NOT bypass the kill switch (`memory-rehydrate-off` file).
- Do NOT delete user-created notes in `memory/<project-slug>/` — only
  files with `source: engram` frontmatter are ours to rotate.
- Do NOT hydrate sensitive scopes (`personal`, `credential`) into the
  filesystem. Enforce the `exclude_scopes` filter.
- Do NOT derive a project-slug without sanitization. Reject slugs
  containing `..`, `/` (leading or nested beyond the first segment),
  NUL bytes, or whitespace. Whitelist pattern: `[a-z0-9-]{1,80}`.
  Fallback on violation: use a SHA256 hex-8 of the cwd path.
- Do NOT rehydrate the same directory in parallel. Acquire the lock with
  `flock(1)` — the POSIX utility that releases the file descriptor
  automatically on process exit, **NOT a naive pidfile** (stale pidfiles
  from killed processes block forever). Concrete pattern:
  ```bash
  exec 9>"~/.claude/memory/<slug>/.rehydrate.lock"
  flock -n 9 || { echo "another rehydrate is running"; exit 1; }
  # ... phases 5 and 3 here ...
  # lock is released automatically when fd 9 closes on exit
  ```
  If the lock is held → abort with "another rehydrate is running".

---

## INTEGRATION WITH ARCA

- **Engram (required):** this skill is inert without the Engram MCP connected. If
  `engram` tools are not available at runtime, abort with a clear message.
- **Memory tool (downstream consumer):** Claude's native memory tool will
  discover these files automatically when it opens the `memory/` directory.
  No extra wiring needed — that's the whole point of the bridge.
- **session_start.sh:** the hook detects stale `memory/` and nudges the
  user. The hook itself does NOT call this skill (bash can't reach MCPs).
- **Ambient monitor (Track B.1):** no direct integration. Ambient handles
  incoming signals; rehydrate handles stored context.

## KILL SWITCHES

- Missing Engram MCP → abort, report.
- Target directory not writable → abort, report.
- Config JSON malformed → fall back to defaults, log warning.
- More than 50 files would be written → abort with "cap" message, ask user.

## ROLLBACK

If rehydration corrupts `memory/<project-slug>/`, delete the directory:

```bash
rm -rf ~/.claude/memory/<project-slug>
```

Next invocation regenerates from scratch. Engram is the source of truth;
the memory/ directory is disposable cache.
