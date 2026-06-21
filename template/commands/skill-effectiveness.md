---
description: Aggregate skill telemetry from the last N weeks and flag skills below a success-rate threshold as candidates for manual review by ⟦ user_name ⟧. NEVER auto-rewrites.
allowed-tools: Bash(bash*)
---

`$ARGUMENTS` carries optional flags: `--weeks N` and `--threshold X`.
Defaults are `--weeks 4` and `--threshold 0.7`. Same flow as
`skills/skill-effectiveness/SKILL.md` — that file is the single source
of truth. This markdown exposes the slash command for direct invocation.

## Uso

```
/skill-effectiveness                       # last 4 weeks, threshold 0.7
/skill-effectiveness --weeks 8             # last 8 weeks, default threshold
/skill-effectiveness --threshold 0.6       # default window, 60% threshold
/skill-effectiveness --weeks 2 --threshold 0.5
```

## Proceso

All executable logic lives in `skills/skill-effectiveness/run.sh`. The
bash block below captures `$ARGUMENTS` inside a single-quoted heredoc
(`<<'ARCA_SKILL_EFF_EOF'`): bash guarantees zero expansion in the body,
so `$(...)`, backticks and `${VAR}` land as literal bytes in
`ARGS_RAW`. The captured payload then flows into `run.sh` via stdin
(no argv exposure) so the script can split flags safely. The pattern
is the canonical ADR-007 / ARCA-SEC-1 hardening.

A multi-line `$ARGUMENTS` could close the heredoc prematurely if the
attacker injects the literal delimiter on its own line. Since
`/skill-effectiveness` flags are always single-line, we reject any
embedded newline before invoking `run.sh`.

```bash
ARGS_RAW=$(cat <<'ARCA_SKILL_EFF_EOF'
$ARGUMENTS
ARCA_SKILL_EFF_EOF
)
# Heredoc appends a trailing newline; strip it so the args round-trip exactly.
ARGS_RAW="${ARGS_RAW%$'\n'}"

# Reject multi-line: any embedded newline = potential heredoc-terminator injection (ARCA-SEC-1 B1).
case "$ARGS_RAW" in
  *$'\n'*)
    echo "[/skill-effectiveness] ENTORNO: argumentos multi-linea no permitidos (ARCA-SEC-1 B1)." >&2
    echo "  /skill-effectiveness acepta solo flags en una linea." >&2
    exit 2
    ;;
esac

printf '%s' "$ARGS_RAW" | bash "${CLAUDE_PROJECT_DIR:-${PWD}}/skills/skill-effectiveness/run.sh"
```

## Output

`~/.claude/state/skill-effectiveness/<YYYY-Www>.md` with:

- Header: weeks scanned, threshold, total invocations
- Table of flagged skills sorted by success_rate ascending:
  `| skill | total | success | fail | unknown | rate |`
- Mandatory text: *"These skills are CANDIDATES for manual review.
  ⟦ user_name ⟧ decides whether to rewrite. NEVER auto-rewrite."*
- If 0 flagged: *"No skills below threshold this period."*

The flagging rule is arithmetic and unambiguous:

```
success_rate = success / (success + fail)   # unknown excluded from denominator
flag iff (success + fail + unknown) >= 10  AND  success_rate < threshold
```

## Anti-patterns

- NO uses `/skill-effectiveness` para reescribir skills automaticamente.
  El comando solo reporta. ⟦ user_name ⟧ sign-off es no-negociable.
- NO uses thresholds extremos (>0.95 o <0.3): el 70% por defecto es el
  punto donde una skill muestra patron consistente de fallo, no ruido.
- NO confies en una sola semana de telemetria; el minimo de 10 usos por
  skill es deliberado para evitar flag-on-tail.
