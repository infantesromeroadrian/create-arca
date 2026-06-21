# Attribution

**Source:** https://github.com/mattpocock/skills (skills/diagnose/)
**Author:** Matt Pocock (Total TypeScript creator)
**License:** MIT
**Installation method:** `npx skills@latest add mattpocock/skills -s diagnose --global -y --copy`
**Snapshot date in ARCA:** 2026-05-04

## License terms

MIT — copy + redistribute permitted with attribution. ARCA preserves the SKILL.md and scripts/ verbatim from the upstream snapshot.

## Why this skill is in ARCA

Adopted on 2026-05-04 to complement `@code-critic` and `@math-critic` with a disciplined bug-diagnosis methodology. The skill encodes a 6-step loop (reproduce → minimise → hypothesise → instrument → fix → regression-test) that is rigorous enough to catch performance regressions in ML training loops, edge cases in prompt-injection guards, and silent data leaks in pipelines. ARCA's existing gates verify *correctness* but didn't formalize the *diagnostic process* until now.

## Name coexistence note

ARCA already ships a slash command `/diagnose` (description: "Diagnóstico completo del proyecto. Estructura, dependencias, issues potenciales") that lives in `commands/diagnose.md`. The Matt Pocock skill `diagnose` is NOT the same artifact — slash commands are user-invokable via `/<name>` and live in commands/, while skills are auto-routed by `@skill-router` based on description matching and live in skills/. Both can coexist in different namespaces. If you want to invoke the slash command type `/diagnose`; if you want the skill, ARCA's skill-router will load it when your prompt matches the description ("diagnose this", "debug this", reports a bug, etc).

Updates: re-run the install command above, then `cp -r ~/.claude/skills/diagnose/* skills/diagnose/`.
