#!/usr/bin/env bash
# ARCA — Always-On Orchestration Reflex (ADR-091)
#
# UserPromptSubmit hook. Fires BEFORE the model sees the user prompt. For a
# DOMAIN task it prepends an imperative routing directive so the general agent
# (main loop) proposes routing to the owning specialist instead of freelancing
# the work in prose — the documented recurring failure (Engram
# `feedback_orchestration_discipline`).
#
# HONEST LIMIT (ADR-091): a hook CANNOT force the model to call a tool. Hooks
# gate tool calls, not the model's decision NOT to call one. There is no hook
# that blocks the main loop from answering in prose. This is STEERING at the
# point of maximum leverage (the user turn, before the model reasons), not a
# cage. It changes behaviour far more than static CLAUDE.md prose because it is
# contextual, prompt-specific, and re-injected every turn — but the model can
# still ignore it. The downstream PreToolUse:Agent backstop
# (delegation-preflight-enforcer.sh) only catches the case where ARCA DOES
# delegate but skips preflight.
#
# Contract (same as user-prompt-context-injector.sh): stdin = JSON with at
# least { "prompt": "..." }; anything written to stdout is prepended to the
# prompt; exit 0 ALWAYS (never blocks).
#
# Three layers (cheap-to-expensive):
#   Layer 0 — SKIP (silent): slash command / <30 chars / pure-conversation
#             (question opener AND no action verb, e.g. "qué es un VPC").
#   Layer 1 — DOMAIN: a domain signal matched → inject imperative directive
#             naming the owning specialist + ADR-089 proposal format.
#   Layer 2 — AMBIGUOUS: an action verb but no recognised domain → soft nudge.
#
# The bias is deliberate: Layer 1 prefers a false positive (one extra nudge,
# ~40 tokens) over a false negative (a specialist never called = a whole task
# done wrong). Layer 0 is implacably silent — noise on chit-chat trains the
# operator to ignore the reflex, and an ignored reflex is worse than none.
#
# Disable entirely: ARCA_ORCHESTRATION_REFLEX_DISABLE=1.
# Test override: ARCA_ORCHESTRATION_REFLEX_DISABLE honoured; reads stdin only.

set -uo pipefail

payload="$(cat -)"
command -v jq >/dev/null 2>&1 || exit 0
prompt=$(printf '%s' "$payload" | jq -r '.prompt // empty' 2>/dev/null || echo "")
[[ -z "$prompt" ]] && exit 0

# session is parsed here (not lower) because the ADR-102 turn reset below must
# run on EVERY turn — including slash / short ones — so a domain turn's state
# never leaks into the next turn. record() (SF-1) reuses this same $session.
session=$(printf '%s' "$payload" | jq -r '.session_id // empty' 2>/dev/null || echo "")
session="${session:0:36}"

# --- ADR-102 proposal-gate turn state --------------------------------------
# Reset the gate's per-session state every turn, then (after classification)
# stamp the domain/specialist/tier on a domain turn. proposal-gate.sh
# (PreToolUse) READS this; this hook is the only writer of the reset+domain.
# Fail-safe: pg_set NEVER alters this hook's exit-0 contract. INERT in effect
# until proposal-gate.sh itself is registered in settings.json (ADR-102 §5) —
# until then this only populates state nobody reads (cheap, audit-useful).
#
# main_pid: this hook runs ONLY on the main loop's UserPromptSubmit, so the
# claude-ancestor PID captured here IS the main loop's. proposal-gate.sh
# compares against it to grant subagents turn-INDEPENDENT immunity (ADR-102
# §5.6) — the fix for the Agent-Teams cross-turn leak the adversarial review
# found. Empty if claude-process-id.sh can't resolve (gate then falls back to
# the agent_dispatched flag).
PROPOSAL_GATE_STATE="${ARCA_PROPOSAL_GATE_STATE:-${HOME}/.claude/state/proposal-gate.json}"
PG_MAIN_PID=""
pg_cpid_lib="$(dirname "${BASH_SOURCE[0]}")/lib/claude-process-id.sh"
[[ -r "$pg_cpid_lib" ]] && PG_MAIN_PID=$(bash "$pg_cpid_lib" 2>/dev/null || echo "")
pg_set() {  # domain specialist tier — overwrite THIS session's turn state
  [[ "${ARCA_PROPOSAL_GATE_DISABLE:-0}" == "1" ]] && return 0
  [[ -z "$session" ]] && return 0
  local dir lock tmp
  dir="$(dirname "$PROPOSAL_GATE_STATE")"
  mkdir -p "$dir" 2>/dev/null || return 0
  [[ -w "$dir" ]] || return 0
  lock="${PROPOSAL_GATE_STATE}.lock"
  ( flock -w 1 9 || exit 0
    [[ -f "$PROPOSAL_GATE_STATE" ]] || echo '{}' > "$PROPOSAL_GATE_STATE" 2>/dev/null
    tmp="${PROPOSAL_GATE_STATE}.tmp.$$"
    if jq --arg s "$session" --arg d "$1" --arg sp "$2" --arg t "$3" --arg mp "$PG_MAIN_PID" \
          '.[$s] = {domain:$d, specialist:$sp, tier:$t, primitives:0, agent_dispatched:false, main_pid:$mp}' \
          "$PROPOSAL_GATE_STATE" > "$tmp" 2>/dev/null; then
      mv "$tmp" "$PROPOSAL_GATE_STATE" 2>/dev/null
    else
      rm -f "$tmp"
    fi
  ) 9>"$lock"
  return 0
}
# The reset runs every turn (pg_set itself honours ARCA_PROPOSAL_GATE_DISABLE,
# so ALL its call sites — reset and the domain stamps below — are gated by the
# one switch). Running it here, BEFORE the reflex-disable check below, is the
# fix for the stale-domain leak the adversarial review found ("reflex off, gate
# on"); the two switches stay independent (ADR-102 §5.5).
pg_set "" "" ""

# Reflex's OWN disable — skips only the banner/classification from here on. The
# proposal-gate reset above has already run, so disabling the reflex never
# leaves stale gate state.
[[ "${ARCA_ORCHESTRATION_REFLEX_DISABLE:-0}" == "1" ]] && exit 0

# --- Layer 0: skip slash commands and trivially short prompts --------------
[[ "$prompt" =~ ^/[A-Za-z] ]] && exit 0
[[ "${#prompt}" -lt 30 ]] && exit 0

# case-insensitive substring/regex test against the prompt
matches() { printf '%s' "$prompt" | grep -iqE "$1"; }

# --- SF-1 telemetry (MECH-03) ----------------------------------------------
# A steering hook that leaves no trace cannot be iterated on ("to iterate you
# must understand effects"). The audit found 0 log writes here, so the only
# fire-rate evidence was replay — not real injections. record() appends ONE
# JSONL line per substantive decision so the reflex becomes auditable: how
# often it fires, in which tier, on which domain, vs how often it stays silent
# and why. Correlating `fired` events against whether the model then delegated
# is the post-hoc analysis the proposal-gate (ADR-PROPOSAL-GATE) will build on.
#
# Fail-safe is the load-bearing property: a telemetry write must NEVER alter
# the hook's exit-0 contract. Every failure path returns 0 (dir not writable,
# jq error, read-only file). jq existence is already guaranteed above (line ~44
# exits if absent), so record() does not re-check it.
#
# ONLY metadata is logged — never the prompt body (size + it may carry
# secrets). Slash / <30-char / missing-jq exits are intentionally NOT recorded:
# they are non-substantive, and slash is already covered by
# slash-command-telemetry.sh. The logged universe is exactly the set of prompts
# that reached domain classification — the right denominator for the fire-rate.
# ($session is parsed above, before the Layer-0 exits, for the ADR-102 reset.)
REFLEX_TELEMETRY="${ARCA_REFLEX_TELEMETRY:-${HOME}/.claude/state/reflex-telemetry.jsonl}"

record() {  # decision  reason  domain  tier   (domain/tier may be empty)
  local dir ts
  dir="$(dirname "$REFLEX_TELEMETRY")"
  mkdir -p "$dir" 2>/dev/null || return 0
  [[ -w "$dir" ]] || return 0
  [[ -e "$REFLEX_TELEMETRY" && ! -w "$REFLEX_TELEMETRY" ]] && return 0
  ts="$(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S%z')"
  jq -nc \
    --arg ts "$ts" --arg decision "$1" --arg reason "$2" \
    --arg domain "$3" --arg tier "$4" --arg session "$session" \
    '{ts:$ts, decision:$decision, reason:$reason, domain:$domain, tier:$tier, session:$session}' \
    >> "$REFLEX_TELEMETRY" 2>/dev/null || return 0
}

# --- Action-signal detection -----------------------------------------------
# Spanish imperative stems are \b-bounded so they discriminate intent
# ("configura X") from declarative conjugations ("configuramos X ayer"). English
# noun-verbs (build/deploy/commit/push/train) are EXCLUDED — they live only as
# domain keywords — so "el commit rompió la build" / "por qué falló el deploy"
# carry no action signal. ⟦ user_name ⟧ works in Spanish; the EN set is the conservative
# unambiguous-verb subset.
ACTION_IMP='\b(implementa|crea|configura|entrena|reentrena|despliega|instala|arregla|escribe|monta|construye|refactoriza|optimiza|audita|analiza|valida|dise(n|ñ)a|planifica|explota|ataca|integra|migra|genera|lanza|ejecuta|conecta|revisa|a[nñ]ade|actualiza|elimina|borra|codea|implement|create|install|refactor|configure|optimize|migrate|integrate|generate|write|setup)\b'

# Strong intent markers — almost always task-intent on their own. (Spanish only:
# English markers moved to ACTION_WEAK_EN below — unanchored "i want|i need|please|
# can you" matched anywhere and routed polite chit-chat with a domain noun.)
ACTION_STRONG='vamos a|hay que|tengo que|tenemos que|h[aá]zme|\bhaz |ay[uú]dame'

# Weak intent markers (quiero/necesito/puedes/...) — count as an action signal
# ONLY when FOLLOWED within ~2 words by an action-verb STEM (A4 fix). Kills the
# false positive where a weak marker co-occurs with an unrelated domain noun:
# "necesito vacaciones pero el commit me preocupa" and "puedes estar tranquilo
# que el deploy salió" stay silent, while "necesito que configures X" and
# "puedes montar el rag" still route.
ACTION_STEM='configur|mont|despleg|implement|instal|refactor|optimiz|audit|integr|migr|gener|lanz|ejecut|conect|revis|valid|planific|analiz|code|actualiz|elimin|borr|reentren|entren|cre[ao]|escrib|arregl|aplic|dise|atac|explot|construy|a[nñ]ad'
ACTION_WEAK='(quiero|queremos|necesito|necesitamos|puedes|podr[ií]as|me gustar[ií]a)[[:space:]]+([a-z]+[[:space:]]+){0,2}('"$ACTION_STEM"')'

# English weak markers — same A4 treatment as the Spanish ones: count as an action
# signal ONLY when FOLLOWED within ~2 words by an unambiguous action-verb STEM.
# "i need a coffee", "please dont worry the commit was reviewed", "i want to
# understand the rag" stay silent; "i need you to configure" / "please set up the
# rag" route. EN noun-verbs (build/deploy/commit/push/train) remain domain-only.
# Full base verbs with \b on BOTH sides — NOT bare prefixes. A prefix like `creat`
# substring-matches `creative`/`creature` and `install` matches `installation`,
# re-introducing the very chit-chat false positive this fix exists to kill
# ("i need creative input on the rag" must stay silent). The base verb `create`
# is not a substring of `creative` (6th char differs) and `\binstall\b` does not
# match `installation`. After "i need (you) to ..." the verb is in base form, so
# base verbs (not gerund stems) are the right match; gerund forms are a rare,
# accepted miss in this conservative EN subset.
ACTION_STEM_EN='\b(implement|create|install|refactor|configure|optimize|migrate|integrate|generate|write|set[[:space:]]?up)\b'
ACTION_WEAK_EN='(i want|i need|please|can you|could you|i.?d like|i would like)[[:space:]]+(to[[:space:]]+|you[[:space:]]+to[[:space:]]+)?([a-z]+[[:space:]]+){0,2}('"$ACTION_STEM_EN"')'

ACTION_VERB="(${ACTION_IMP}|${ACTION_STRONG}|${ACTION_WEAK}|${ACTION_WEAK_EN})"

# Pure-conversation openers (state / clarify / what-why-how). Anchored at start.
PURE_Q='^[[:space:]]*(qu[eé]|c[oó]mo|por[[:space:]]?qu[eé]|porqu[eé]|cu[aá]l|explica|expl[ií]came|resume|status|estado|d[oó]nde|cu[aá]ndo|what|why|how|which|where|when|explain|summarize)\b'

# Declarative-subject guard: a prompt that OPENS with a subject determiner
# (el/la/mi/este...) and carries no request marker is an observation about a
# thing, not a command. Catches the irreducible homograph where 3rd-person
# present == tú-imperative for -ar verbs ("el script entrena solo", "mi
# compañero configura el docker") without silencing verb-first commands (which
# never open with a determiner) — subject-first requests keep a request marker.
DECL_SUBJECT='^[[:space:]]*(el|la|los|las|mi|tu|su|sus|este|esta|ese|esa|estos|estas|nuestro|nuestra)[[:space:]]'
REQUEST_MARKER='(vamos a|hay que|tengo que|tenemos que|h[aá]zme|\bhaz |ay[uú]dame|necesit|quier|por favor|hace falta|debe[ns]?[[:space:]])'

# Layer 0a: pure conversation = a question opener AND no action signal.
if matches "$PURE_Q" && ! matches "$ACTION_VERB"; then
  record silent pure_question "" ""
  exit 0
fi

# Layer 0a-bis: pedagogical "how is X done". A question opener PLUS the
# "cómo se <verbo>" / "how is/are/do/to <X>" construction asks to EXPLAIN a process,
# not perform it — let the question guard win even though an action-verb stem appears
# as the TOPIC. ("explica como se entrena un modelo" → silent, not a training order.)
PEDAGOGICAL_HOWTO='(c[oó]mo[[:space:]]+se[[:space:]]+[a-z]|how[[:space:]]+(is|are|do|does|to)[[:space:]])'
if matches "$PURE_Q" && matches "$PEDAGOGICAL_HOWTO"; then
  record silent pedagogical "" ""
  exit 0
fi

# Layer 0b: declarative-subject guard (see above) — observation, not command.
if matches "$DECL_SUBJECT" && ! matches "$REQUEST_MARKER"; then
  record silent declarative "" ""
  exit 0
fi

# Layer 0c (B1 gate): route ONLY on an action signal. A declarative that merely
# MENTIONS a domain noun has no intent to act and MUST stay silent — otherwise
# the reflex fires on chit-chat and the operator learns to ignore it (the exact
# failure mode this hook exists to prevent).
if ! matches "$ACTION_VERB"; then
  record silent no_action_verb "" ""
  exit 0
fi

# --- Layer 1: domain classification (first match wins; specific -> generic) -
domain=""
specialist=""
if   matches '\b(commit|push|merge|rebase|cherry-pick)\b|pull request|abre .{0,20}\bpr\b'; then domain="git mutation"; specialist="@git-master"
elif matches '\b(aws|ec2|\bs3\b|\biam\b|lambda|sagemaker|bedrock|\becs\b|\beks\b|cloudformation)\b'; then domain="AWS/cloud"; specialist="@aws-engineer"
elif matches '\b(cisco|ospf|\bbgp\b|eigrp|vlan|subred|subnet|containerlab|packet[[:space:]]?tracer|\bpkt\b|\bfrr\b|switching|topolog[ií]a.*red)\b'; then domain="networking (Cisco)"; specialist="@network-engineer"
elif matches '\b(htb|hackthebox|\bctf\b|exploit|\bcve\b|pentest|red[[:space:]-]?team|vuln|\bnmap\b|payload|jailbreak)\b'; then domain="security/red-team"; specialist="@htb-orchestrator or @ai-redteam-orchestrator"
elif matches '\b(entrena|train|fine[[:space:]-]?tun|modelo|dataset|epoch|gradient|qlora|\blora\b|checkpoint)\b'; then domain="ML/training"; specialist="@ml-engineer / @dl-engineer"
elif matches '\b(rag|retrieval|embedding|langchain|langgraph|vector|chunk|agente|reranker)\b'; then domain="LLM/RAG/agent"; specialist="@ai-engineer / @rag-engineer / @agent-engineer"
elif matches '\b(etl|ingesta|pipeline.*datos|data[[:space:]-]?pipeline|limpia.*datos|valida.*datos|\bschema\b|\bdbt\b|airflow)\b'; then domain="data"; specialist="@data-engineer / @data-validator"
elif matches '\b(docker|kubernetes|\bk8s\b|dockerfile|compose|terraform|ci/cd|helm|despliega|deploy)\b'; then domain="infra/devops"; specialist="@devops"
elif matches '\b(planifi|planning|roadmap|sprint|kanban|backlog|panel|dashboard|organiza.*proyecto)\b'; then domain="planning"; specialist="@project-planner"
elif matches '\b(arquitectura|architecture|dise(n|ñ)a.*sistema|\badr\b|trade[[:space:]-]?off)\b'; then domain="architecture"; specialist="@architect-ai"
elif matches '\b(implementa|refactoriza|codea)\b|crea .{0,25}(funci|clase|m[oó]dul|script)|escribe .{0,25}(funci|script|c[oó]digo)|arregla .{0,20}bug'; then domain="code"; specialist="@python-specialist (or the domain code agent)"
fi

# --- ADR-101: two-tier proposal. TIER-LITE for single-specialist, reversible
# domains (git / a single code edit / planning-docs) with NO adversarial signal;
# TIER-FULL (the ADR-089 DAG proposal) for producer-chains (ML/RAG/data), deploy/
# security/AWS/networking, architecture, OR whenever ANY of the 7 adversarial
# signals appears in the prompt. Fail toward FULL on ambiguity (same bias as
# ADR-099). The runtime hooks fire identically in both tiers — this lightens the
# PROPOSAL text, never the enforcement (the audit's load-bearing safety claim).
# Note: diffuse signals like "unvalidated input" are not regex-detectable; this
# catches the clear lexical ones (auth/token/PII/oauth/upload/endpoint/prod).
# Stems WITHOUT a trailing \b so Spanish plurals/inflections match (credencial->
# credenciales, sensibl->sensibles, token->tokens, secreto->secretos, contrase->
# contraseñas/contrasenas) — same convention as ACTION_STEM. `producción`/`público`
# are deliberately EXCLUDED: too frequent + benign ("commit del informe de producción")
# and would over-escalate git/planning, defeating TIER-LITE. Endpoint exposure is
# still caught via the literal `endpoint` cue.
ADV_SIGNAL='(\bendpoint|\bauth\b|autenticaci|\blogin|password|contrase|secreto|\bsecrets?\b|\btoken|credencial|credential|api[[:space:]]?key|\bpii\b|\bgdpr\b|sensibl|sensitiv|oauth|\bupload|webhook)'
TIER="full"
case "$domain" in
  "git mutation"|"code"|"planning")
    if matches "$ADV_SIGNAL"; then TIER="full"; else TIER="lite"; fi ;;
esac

if [[ -n "$specialist" ]]; then
  if [[ "$TIER" == "lite" ]]; then
    record fired domain_match "$domain" lite
    pg_set "$domain" "$specialist" lite
    printf '<arca-orchestration-reflex>\n'
    printf 'DOMAIN TASK DETECTED: %s (TIER-LITE — single-specialist, reversible, no adversarial signal). Propose routing in ONE line, e.g. "Routing to %s + @code-critic. Procedo?" — NO full DAG / per-node-gate table (ADR-101). The runtime hooks (preflight, critic gates, ADR-100 cap) STILL fire on the actual Agent call; this lightens the proposal, not the enforcement. Get ⟦ user_title ⟧ OK, then preflight (token-optimizer -> skill-router -> specialist).\n' "$domain" "$specialist"
    printf '</arca-orchestration-reflex>\n\n'
    exit 0
  fi
  record fired domain_match "$domain" full
  pg_set "$domain" "$specialist" full
  printf '<arca-orchestration-reflex>\n'
  printf 'DOMAIN TASK DETECTED: %s (TIER-FULL). Before executing, you MUST propose an Orchestration Proposal in natural language — owning specialist(s): %s; the agent DAG + order; the adversarial critics + blocking gates per node — then get ⟦ user_title ⟧ approval, then route via preflight (token-optimizer -> skill-router -> specialist). Do NOT freelance domain work in prose. Always-on reflex per ADR-091 + ADR-101.\n' "$domain" "$specialist"
  printf '</arca-orchestration-reflex>\n\n'
  exit 0
fi

# --- Layer 2: action verb but no recognised domain -> soft nudge -----------
if matches "$ACTION_VERB"; then
  record soft_nudge no_domain "" ""
  printf '<arca-orchestration-reflex>\n'
  printf 'If this is domain work, name the owning specialist and propose routing (specialist + critics/gates) before executing — do not freelance. Always-on reflex per ADR-091.\n'
  printf '</arca-orchestration-reflex>\n\n'
  exit 0
fi

exit 0
