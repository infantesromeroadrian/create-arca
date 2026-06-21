# create-arca

**Mint your own ARCA — a Claude Code agent orchestrated by 59 specialist subagents, 145 skills, enforced gates and full ML/security/infra pipelines — in one command.**

```bash
uvx create-arca
```

That's it. Answer a handful of questions and you get a complete, opinionated Claude Code harness wired into `~/.claude`: a routing orchestrator, a roster of domain specialists, adversarial critic gates that block bad work *before* it lands, and a personality that never approves on the first pass.

---

## What is ARCA?

Most "AI agents" are one big prompt. ARCA is a **system**: a main loop that does not execute domain work itself — it *routes* every task to the right specialist, runs it through blocking quality gates, and refuses to ship until the work is right.

- **59 specialist subagents** — ML, deep learning, RL, data, MLOps, RAG, cloud, Kubernetes, security/red-team, frontend, and the critics that police them.
- **Hard gates that actually block** — code-critic, math-critic, secret detection, conventional-commit enforcement, delegation preflight. These are real hooks, not vibes.
- **Three pipelines** — a 14-cycle ML lifecycle, a CVE-first HTB/CTF flow, and a 9-phase AI red-team pipeline.
- **A character** — ARCA is a severe architect: dry, demanding, allergic to AI slop. You can keep that voice or dial it to "professional" — but it speaks as *you*, to *you*.

## Quickstart

```bash
# Render ARCA into ~/.claude (the default)
uvx create-arca

# ...or into a specific directory
uvx create-arca ./my-arca
```

The wizard asks for your name, how the agent should address you, which model tiers you have, and **which domains you want** — so a data scientist doesn't get handed 14 penetration-testing agents.

## Profiles — install only what you need

| Profile    | Adds on top of `core`                                              |
|------------|-------------------------------------------------------------------|
| `core`     | Orchestration spine, critics, architecture, utility, quality *(always)* |
| `ml`       | Data, training, MLOps, RAG, evals + the 14-cycle ML pipeline       |
| `security` | HTB/CTF, AI red-team, bug bounty + HTB & ART pipelines             |
| `infra`    | Cloud, Kubernetes, serving, monitoring, networking                |
| `web`      | Frontend AI, API contracts, low-level systems                     |
| `all`      | Everything — all 59 agents and every pipeline                     |

## It's a living harness, not a one-shot scaffold

ARCA is shipped as a [Copier](https://copier.readthedocs.io) template. When a new ARCA release lands, pull it into your existing install **without losing your customization**:

```bash
copier update
```

Your name, your tone, your profile — all preserved. You ride upstream improvements like a dependency, not a fork.

## How it works

`create-arca` renders a [Copier](https://copier.readthedocs.io) template (`template/`) into your `~/.claude`. Every personal detail is a variable, so you install *ARCA-the-architect* but the harness knows *you*. The hard gates work out of the box; the optional local LLM-as-judge (Ollama) powers the softer advisory gates if you enable it.

## Security

ARCA was extracted from a private, personal harness. The published template is **derived**, never copied: a maintainer-side scrubber replaces every identity marker with a variable and strips hard secrets, and CI re-scans every commit — for leftover markers, for any bare UUID (org-id shape), and with `gitleaks` for generic secret material. A leak fails the build. See [`scrub/patterns.toml`](scrub/patterns.toml).

## Contributing

The agents, skills, hooks and commands live in `template/` as plain Markdown and Bash — edit those, never the engine. `scrub/` and `scripts/scrub.py` are maintainer tooling for re-deriving the template from upstream.

## License

MIT — see [LICENSE](LICENSE).
