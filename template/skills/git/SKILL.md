---
name: git
description: Complete guide for Git version control and GitHub workflows including commits, branches, PRs, merge strategies, conventional commits, GitHub CLI, and collaboration patterns. Use when managing code versions, collaborating on projects, or setting up Git workflows.
---

# Git & GitHub

## Quick Reference

| Task | Command |
|------|---------|
| Clone repo | `git clone <url>` |
| Create branch | `git checkout -b feature/name` |
| Stage all | `git add .` |
| Commit | `git commit -m "message"` |
| Push | `git push -u origin branch` |
| Pull latest | `git pull --rebase` |
| View history | `git log --oneline -20` |
| Undo last commit | `git reset --soft HEAD~1` |

---

## Configuration

### Initial Setup

```bash
# Identity
git config --global user.name "Your Name"
git config --global user.email "your@email.com"

# Default branch
git config --global init.defaultBranch main

# Editor
git config --global core.editor "code --wait"  # VS Code
git config --global core.editor "vim"          # Vim

# Aliases (productivity)
git config --global alias.co checkout
git config --global alias.br branch
git config --global alias.ci commit
git config --global alias.st status
git config --global alias.lg "log --oneline --graph --decorate -20"
git config --global alias.last "log -1 HEAD --stat"
git config --global alias.unstage "reset HEAD --"
git config --global alias.amend "commit --amend --no-edit"

# Better defaults
git config --global pull.rebase true
git config --global fetch.prune true
git config --global diff.colorMoved zebra
git config --global rebase.autoStash true

# View all config
git config --list --show-origin
```

### SSH Setup

```bash
# Generate key
ssh-keygen -t ed25519 -C "your@email.com"

# Start agent
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519

# Copy public key
cat ~/.ssh/id_ed25519.pub
# Add to GitHub: Settings → SSH and GPG keys

# Test connection
ssh -T git@github.com
```

### GPG Signing

```bash
# Generate GPG key
gpg --full-generate-key

# List keys
gpg --list-secret-keys --keyid-format=long

# Configure Git
git config --global user.signingkey YOUR_KEY_ID
git config --global commit.gpgsign true

# Export for GitHub
gpg --armor --export YOUR_KEY_ID
```

---

## Conventional Commits

### Format

```
<type>(<scope>): <subject>

[optional body]

[optional footer(s)]
```

### Types

| Type | Description | Example |
|------|-------------|---------|
| `feat` | New feature | `feat(auth): add OAuth2 login` |
| `fix` | Bug fix | `fix(api): handle null response` |
| `docs` | Documentation | `docs: update README setup` |
| `style` | Formatting | `style: fix indentation` |
| `refactor` | Code restructure | `refactor: extract helper fn` |
| `perf` | Performance | `perf(db): add query index` |
| `test` | Tests | `test: add unit tests for auth` |
| `build` | Build system | `build: upgrade webpack` |
| `ci` | CI config | `ci: add deploy workflow` |
| `chore` | Maintenance | `chore: update deps` |
| `revert` | Revert commit | `revert: feat(auth)...` |

### Breaking Changes

```bash
# In subject (with !)
feat(api)!: change response format

# In footer
feat(api): change response format

BREAKING CHANGE: Response now returns array instead of object
```

### Examples

```bash
# Simple
git commit -m "feat(auth): add password reset flow"

# With body
git commit -m "fix(api): handle rate limit errors

Add exponential backoff retry logic when API returns 429.
Max retries: 3, initial delay: 1s.

Closes #123"

# Breaking change
git commit -m "feat(api)!: v2 endpoints

BREAKING CHANGE: All endpoints now require API key header"
```

---

## Branching Strategies

### Git Flow

```
main (production)
  │
  └── develop (integration)
        │
        ├── feature/user-auth
        ├── feature/payment
        │
        └── release/1.0.0
              │
              └── hotfix/critical-bug → main & develop
```

```bash
# Feature branch
git checkout develop
git checkout -b feature/user-auth

# Work...
git add .
git commit -m "feat(auth): implement login"

# Merge back
git checkout develop
git merge --no-ff feature/user-auth
git branch -d feature/user-auth

# Release
git checkout -b release/1.0.0 develop
# Bug fixes only...
git checkout main
git merge --no-ff release/1.0.0
git tag -a v1.0.0 -m "Release 1.0.0"
git checkout develop
git merge --no-ff release/1.0.0
```

### GitHub Flow (Simpler)

```
main (always deployable)
  │
  ├── feature/user-auth → PR → main
  ├── fix/login-bug → PR → main
  └── docs/api-guide → PR → main
```

```bash
# Create feature branch
git checkout main
git pull
git checkout -b feature/user-auth

# Work and commit
git add .
git commit -m "feat(auth): add login page"

# Push and create PR
git push -u origin feature/user-auth
gh pr create --fill

# After PR approval and merge
git checkout main
git pull
git branch -d feature/user-auth
```

### Trunk-Based Development

```
main (trunk)
  │
  ├── short-lived branch (< 1 day) → merge
  ├── short-lived branch → merge
  └── feature flags for WIP
```

```bash
# Quick branch
git checkout -b fix/typo
git commit -am "fix: typo in header"
git push -u origin fix/typo
gh pr create --fill
# Merge same day
```

---

## Common Workflows

### Starting New Feature

```bash
# Update main
git checkout main
git pull

# Create branch
git checkout -b feature/new-feature

# Work...
git add .
git commit -m "feat: initial implementation"

# Keep updated with main
git fetch origin
git rebase origin/main

# Push
git push -u origin feature/new-feature
```

### Updating Feature Branch

```bash
# Option 1: Rebase (cleaner history)
git fetch origin
git rebase origin/main
# If conflicts:
git add .
git rebase --continue

# Option 2: Merge (preserves history)
git fetch origin
git merge origin/main
```

### Squashing Commits Before PR

```bash
# Interactive rebase last N commits
git rebase -i HEAD~5

# In editor, change 'pick' to 'squash' or 's'
pick abc123 feat: initial work
squash def456 wip
squash ghi789 more work
squash jkl012 fix tests
squash mno345 final touches

# Save, then edit combined message

# Force push (only on feature branches!)
git push --force-with-lease
```

### Fixing Mistakes

```bash
# Undo last commit (keep changes)
git reset --soft HEAD~1

# Undo last commit (discard changes)
git reset --hard HEAD~1

# Amend last commit message
git commit --amend -m "new message"

# Add to last commit
git add forgotten-file.js
git commit --amend --no-edit

# Undo pushed commit (safe)
git revert HEAD
git push

# Undo changes to file
git checkout -- filename
# Or in newer Git:
git restore filename

# Unstage file
git reset HEAD filename
# Or:
git restore --staged filename
```

### Stashing Work

```bash
# Stash changes
git stash
git stash push -m "work in progress on feature X"

# List stashes
git stash list

# Apply latest stash (keep in stash)
git stash apply

# Apply and remove
git stash pop

# Apply specific stash
git stash apply stash@{2}

# Create branch from stash
git stash branch new-branch stash@{0}

# Clear all stashes
git stash clear
```

### Cherry-Pick

```bash
# Apply specific commit to current branch
git cherry-pick abc123

# Cherry-pick without committing
git cherry-pick --no-commit abc123

# Cherry-pick range
git cherry-pick abc123..def456
```

---

## GitHub CLI (gh)

### Setup

```bash
# Install
# macOS
brew install gh

# Ubuntu
sudo apt install gh

# Authenticate
gh auth login
```

### Common Commands

```bash
# Repository
gh repo create my-project --public
gh repo clone owner/repo
gh repo fork owner/repo
gh repo view --web

# Pull Requests
gh pr create --fill
gh pr create --title "feat: add login" --body "Description"
gh pr list
gh pr view 123
gh pr checkout 123
gh pr merge 123 --squash
gh pr review 123 --approve

# Issues
gh issue create --title "Bug" --body "Description"
gh issue list
gh issue close 123

# Workflow
gh workflow list
gh workflow run deploy.yml
gh run list
gh run view 123
gh run watch

# Releases
gh release create v1.0.0 --generate-notes
gh release download v1.0.0
```

### PR Workflow with gh

```bash
# Create feature branch
git checkout -b feature/awesome

# Work and commit
git add .
git commit -m "feat: awesome feature"

# Push and create PR in one step
git push -u origin feature/awesome
gh pr create --fill --web

# After review, merge
gh pr merge --squash --delete-branch

# Update local
git checkout main
git pull
```

---

## Merge Strategies

### Merge Commit (--no-ff)

```bash
git merge --no-ff feature/branch
```
```
*   Merge branch 'feature/branch'
|\
| * commit 3
| * commit 2
| * commit 1
|/
* previous main commit
```

### Squash Merge

```bash
git merge --squash feature/branch
git commit -m "feat: complete feature"
```
```
* feat: complete feature (squashed)
* previous main commit
```

### Rebase

```bash
git checkout feature/branch
git rebase main
git checkout main
git merge feature/branch  # Fast-forward
```
```
* commit 3
* commit 2
* commit 1
* previous main commit
```

### When to Use

| Strategy | Use When |
|----------|----------|
| Merge commit | Preserve full history, team collaboration |
| Squash | Clean history, atomic features |
| Rebase | Linear history, before PR |

---

## .gitignore

### Common Patterns

```gitignore
# Dependencies
node_modules/
vendor/
venv/
__pycache__/
*.pyc

# Build outputs
dist/
build/
*.egg-info/
.next/

# IDE
.idea/
.vscode/
*.swp
*.swo

# OS
.DS_Store
Thumbs.db

# Environment
.env
.env.local
*.local

# Logs
*.log
logs/

# Testing
coverage/
.pytest_cache/
.coverage

# Secrets (NEVER commit)
*.pem
*.key
secrets.json
credentials.json
```

### Commands

```bash
# Check what would be ignored
git status --ignored

# Remove already tracked file
git rm --cached filename
git rm -r --cached folder/

# Ignore changes to tracked file
git update-index --assume-unchanged filename

# Stop ignoring
git update-index --no-assume-unchanged filename
```

---

## Advanced Commands

### Log & History

```bash
# Pretty log
git log --oneline --graph --decorate --all

# Search commits
git log --grep="fix" --oneline
git log -S "function_name"  # Search code changes
git log --author="name"

# File history
git log --follow -p -- filename

# Who changed what
git blame filename
git blame -L 10,20 filename  # Lines 10-20
```

### Diff

```bash
# Working vs staged
git diff

# Staged vs last commit
git diff --staged

# Between commits
git diff abc123..def456

# Between branches
git diff main..feature/branch

# Stats only
git diff --stat
```

### Reflog (Recovery)

```bash
# View reflog
git reflog

# Recover deleted branch
git checkout -b recovered-branch abc123

# Undo bad rebase
git reset --hard HEAD@{5}
```

### Bisect (Find Bug)

```bash
# Start bisect
git bisect start

# Mark current as bad
git bisect bad

# Mark known good commit
git bisect good abc123

# Git checks out middle commit, test and mark
git bisect good  # or bad

# Repeat until found, then reset
git bisect reset
```

### Worktrees (Multiple Branches)

```bash
# Add worktree for another branch
git worktree add ../project-hotfix hotfix/urgent

# List worktrees
git worktree list

# Remove worktree
git worktree remove ../project-hotfix
```

---

## GitHub Features

### PR Templates

```markdown
<!-- .github/pull_request_template.md -->
## Description
<!-- What does this PR do? -->

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Breaking change
- [ ] Documentation

## Testing
<!-- How was this tested? -->

## Checklist
- [ ] Tests pass
- [ ] Docs updated
- [ ] No breaking changes (or documented)
```

### Issue Templates

```yaml
# .github/ISSUE_TEMPLATE/bug_report.yml
name: Bug Report
description: Report a bug
labels: ["bug"]
body:
  - type: textarea
    id: description
    attributes:
      label: Describe the bug
      placeholder: A clear description...
    validations:
      required: true
  - type: textarea
    id: reproduction
    attributes:
      label: Steps to reproduce
      placeholder: |
        1. Go to...
        2. Click on...
    validations:
      required: true
```

### CODEOWNERS

```
# .github/CODEOWNERS
# Default owners
* @default-team

# Specific paths
/src/api/ @backend-team
/src/ui/ @frontend-team
/docs/ @docs-team
*.md @docs-team
```

---

## Anti-patterns

| [FAIL] Don't | [PASS] Do |
|----------|-------|
| `git push --force` on shared branches | `git push --force-with-lease` on own branches only |
| Commit secrets/credentials | Use .gitignore, env vars |
| Giant commits | Small, atomic commits |
| Vague messages like "fix" | Descriptive conventional commits |
| Commit directly to main | Use feature branches + PRs |
| Rebase public/shared branches | Only rebase local/own branches |
| Ignore merge conflicts | Resolve carefully, test after |
