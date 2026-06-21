# Contributing to ARCA

Thanks for wanting to make ARCA better. This repo is the **public, personal-data-free
harness** — the agents, skills, hooks and commands that anyone installs with
`uvx create-arca`. Contributions improve that shared harness.

## What lives here

```
template/      ← the harness everyone installs (agents, skills, hooks, commands, settings.json)
copier.yml     ← the install wizard (the questions a user answers)
src/           ← the thin CLI wrapper
```

You edit **`template/`** — plain Markdown and Bash. You do **not** need any of the
maintainer's private tooling; it isn't here by design.

## The golden rule: no personal data

This is a public template. **Never commit anyone's real data** — no names, emails,
API keys, tokens, org-ids, machine hostnames, absolute home paths, or employer
names. Use neutral placeholders (`your-name`, `you@example.com`, `~/notes`) or the
Copier variables already in use (`⟦ user_name ⟧`, `⟦ host_os ⟧`, …).

CI enforces this automatically: every PR is scanned for secret material and
org-id-shaped UUIDs, and the template must still render. A leak fails the build.

## How to contribute

1. **Fork** this repo and create a branch.
2. **Edit `template/`** — add or improve an agent/skill/hook/command. Keep the
   existing style (frontmatter, tone, comment density).
3. If your change adds a personalizable detail, make it a Copier variable in
   `copier.yml` rather than hardcoding a value.
4. **Open a pull request.** Describe what it improves and why.
5. CI runs (no-secrets scan + render smoke test). Green is required.

## How contributions are accepted

The maintainer reviews every PR by hand and decides:

- If the change improves the **public** harness → it's merged here, and ships to
  everyone on the next release (`copier update`).
- The maintainer may also fold useful changes into their **own private** instance.
  That direction is manual and at their discretion — the public repo is the
  source of truth for the shared product.

## Releasing (maintainers)

Tag a release; downstream users pull it with `copier update`, keeping their own
personalization intact.

## License

By contributing you agree your contribution is licensed under the repo's MIT License.
