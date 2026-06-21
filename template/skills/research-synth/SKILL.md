---
name: research-synth
description: Paper/article synthesis pipeline for ML/AI research. Given an arxiv ID, HuggingFace paper, URL, or topical query — fetches the source, extracts structured sections (abstract, methods, results, limitations, related work), generates an executive summary aligned with ⟦ user_name ⟧'s active projects, saves persistent notes to Obsidian, and optionally produces an audio brief via NotebookLM. Scoped to ⟦ user_name ⟧'s ML/AI research workflow — not general research.
paths:
  - "**/research/**"
  - "**/papers/**"
  - "**/Projects/Research/**"
effort: high
---

# RESEARCH-SYNTH — paper in, actionable note out

⟦ user_name ⟧ reads papers daily. The bottleneck is not reading comprehension —
it is the gap between "finish reading" and "remember how this connects
to my work in 3 weeks". This skill closes that gap by producing a
structured note ready to retrieve semantically via Engram or browse via
Obsidian.

---

## WHEN TO INVOKE

- User pastes arxiv link, HF paper URL, or paper title.
- User says: "resume este paper", "qué aporta X", "cómo se compara con Y".
- User asks for a topical survey: "qué hay nuevo sobre agentic reasoning 2026".

## WHEN NOT TO INVOKE

- Casual reading — no need to synth a blog post.
- Programming tutorials — use Context7 MCP for library docs.
- Papers >150 pages — too long for one pass, ask user to narrow focus.

---

## INPUT MODES

| Mode | Trigger | Tooling |
|---|---|---|
| arxiv ID | matches `\d{4}\.\d{4,5}(v\d+)?` | `fetch` MCP `arxiv.org/abs/{id}` |
| HuggingFace paper | URL contains `huggingface.co/papers/` | `huggingface` MCP `paper_search` |
| Direct URL | http/https to PDF or HTML | `fetch` MCP with `max_length=30000` |
| Topical query | natural language, no URL | `huggingface` MCP `paper_search(query)` + select top 3 |
| Local PDF | path ends `.pdf` inside repo | `notebooklm` MCP `source_add(file_path=...)` |

---

## SYNTHESIS PROTOCOL

### Phase 1 — acquisition

1. Resolve input to canonical source (arxiv preferred over HF mirror).
2. Fetch the text. Limit to 30k chars unless user says "full".
3. Extract metadata: title, authors, year, venue, arxiv ID.

### Phase 2 — structured extraction

Produce in this order, no reordering:

```yaml
paper_id: "2404.12345"
title: "..."
authors: ["...", "..."]
year: 2026
venue: "ICLR | NeurIPS | arxiv-only | ..."
tl_dr: "Una frase. Qué claim hace el paper, en cristiano."

contribution:
  - novel_idea: "..."
  - empirical_result: "..."
  - benchmark: "..."

method:
  summary_3_lines: |
    ...
  key_equation_or_algorithm: "optional, solo si es el core"

results:
  primary_metric: "X% on benchmark Y"
  vs_baseline: "+N.N% over baseline Z"
  caveats: "..."

limitations:
  - "..."
  - "..."

related_work:
  - ref: "..."
    relation: "extends | contradicts | parallel"

⟦ user_name ⟧_relevance:
  active_projects_impact: "ARCA · Track B · (otros)"
  action_items:
    - "probar en ARCA C4 (Design) si aplica"
    - "reemplazar X del pipeline ML si supera baseline interno"
  skeptical_read: "dónde NO creo el paper — ejemplos de overclaim"
```

### Phase 3 — persistence

Write the YAML block above PLUS a 200-word prose summary to:
- `/Projects/Research/Papers/{paper_id}-{kebab-title}.md` via `obsidian` MCP.
- Engram `mem_save` with key `research.paper.{paper_id}` and the tl_dr + ⟦ user_name ⟧_relevance compressed.

### Phase 4 — optional audio brief

If user says "audio" or "notebook", and the paper is non-trivial (>10k
chars of source):
- Use `notebooklm` MCP `notebook_create` with paper as source.
- `studio_create(artifact_type=audio)` for audio summary.
- Wait for `studio_status` → completed.
- `download_artifact` to `~/Music/ARCA/research-audio/{paper_id}.mp3`.

---

## SKEPTICAL READ (mandatory section)

Every synthesis includes `skeptical_read`. This is the arquitecto's take:

- What part of the claim is overclaim vs real contribution?
- What baseline/control is missing?
- What would falsify it?
- Is the benchmark gamed (cherry-picked, trained on test, tiny n)?
- If this replaced the current state-of-art in ⟦ user_name ⟧'s pipeline, what breaks first?

If the paper is solid, write `skeptical_read: "No major concerns — methodology sound, results reproducible per appendix X."`. Do not pad with manufactured concerns.

---

## TOPICAL SURVEY MODE

When query has no URL, invoke `huggingface.paper_search(query, limit=10)`.
Rank by:

1. Arxiv citations (if available) > HF likes > recency.
2. Filter out papers already in `/Projects/Research/Papers/` (dedup).
3. Pick top 3. Run Phase 2 for each. Produce a comparison matrix at the
   end:

```
| Paper | Core idea | Primary metric | Relevance to ARCA |
|---|---|---|---|
| ... | ... | ... | ... |
```

---

## ANTI-PATTERNS

- Do not synthesize a paper you could not fetch. If fetch fails, say so, do not invent.
- Do not skip `skeptical_read`. Uncritical summaries are worse than useless — they compound hype.
- Do not save to Obsidian if the synth failed mid-way; better no note than half a note.
- Do not call `notebooklm` audio for every paper — costs time and storage. Only on user request or for long sources.
- Do not exceed 300 words of prose in the Obsidian note body. Structured YAML is the source of truth; prose is the 5-second recall.
- Do not produce "⟦ user_name ⟧ relevance" as generic boilerplate. If the paper has no plausible connection to active ARCA projects, write `⟦ user_name ⟧_relevance: tangential — store for future reference only`.

---

## INTEGRATION WITH ARCA

- **Engram:** every synth saves a compact memory entry. Recall via `mem_search("paper.{topic}")`.
- **Obsidian:** persistent canonical note. Full structured YAML + prose.
- **Morning briefing:** if a new paper was synthed in last 24h AND its `⟦ user_name ⟧_relevance` is non-tangential, surface it in the briefing's "Proyectos Activos" section.
- **Ambient monitor:** no direct integration — research is pull-based, not push.

## KILL SWITCHES

- Paper >150 pages without user explicit "synth anyway" → abort with length warning.
- Fetch returns non-English AND user did not request translation → abort with language warning (Spanish/French/etc. papers fine if user reads them, but do not auto-translate).
- `huggingface.paper_search` returns 0 results for a topical query → report honestly, do not fabricate papers.
