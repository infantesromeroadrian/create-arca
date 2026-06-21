#!/usr/bin/env bash
# PostToolUse:Bash — nudge when ARCA uses bash for tasks that should be delegated.
#
# Detects patterns in bash commands that indicate a task was executed directly
# instead of being routed to the appropriate agent/skill/MCP. Emits a stderr
# warning (non-blocking) to build routing awareness over time.
#
# This is a NUDGE, not a BLOCKER. Exit 0 always. The goal is to surface
# routing opportunities, not to prevent work.

set -euo pipefail

INPUT=$(cat)

command -v jq >/dev/null 2>&1 || exit 0

COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || echo "")
[[ -z "$COMMAND" ]] && exit 0

NUDGE=""

# Infra installs → @devops
if echo "$COMMAND" | grep -qE '(pacman -S|apt install|dnf install|brew install|paru -S)'; then
    NUDGE="[ROUTING-NUDGE] CLI install detected → consider @devops for infra management + HOST_ENVIRONMENT.md update"
fi

# Git mutations → @git-master
if echo "$COMMAND" | grep -qE 'git (commit|merge|rebase|push|tag|branch -[dD]|checkout -b)'; then
    NUDGE="[ROUTING-NUDGE] git mutation detected → consider @git-master (ORCHESTRATOR_BEHAVIOR §8)"
fi

# Terraform → @devops + @aws-engineer
if echo "$COMMAND" | grep -qE '(terraform (init|plan|apply|destroy))'; then
    NUDGE="[ROUTING-NUDGE] terraform operation → consider @devops + @aws-engineer"
fi

# Docker build/run → @devops
if echo "$COMMAND" | grep -qE 'docker (build|run|compose)'; then
    NUDGE="[ROUTING-NUDGE] docker operation → consider @devops or mcp__docker__*"
fi

# kubectl/helm → @devops
if echo "$COMMAND" | grep -qE '(kubectl (apply|create|delete|patch|scale)|helm (install|upgrade|uninstall))'; then
    NUDGE="[ROUTING-NUDGE] K8s operation → consider @devops"
fi

# Python script execution → @python-specialist
if echo "$COMMAND" | grep -qE 'python3? .*\.py' | grep -vqE '(test_|pytest|ruff|bandit)'; then
    NUDGE="[ROUTING-NUDGE] Python script → consider @python-specialist for review"
fi

# Web search via curl → MCP
if echo "$COMMAND" | grep -qE 'curl.*(google|search|api\.)'; then
    NUDGE="[ROUTING-NUDGE] web request → consider mcp__brave__*, mcp__exa__*, or mcp__fetch__*"
fi

# AWS CLI → @aws-engineer
if echo "$COMMAND" | grep -qE 'aws (iam|ec2|s3api|sagemaker|bedrock|lambda create|ecs|eks)'; then
    NUDGE="[ROUTING-NUDGE] AWS operation → consider @aws-engineer"
fi

if [[ -n "$NUDGE" ]]; then
    echo "$NUDGE" >&2
fi

exit 0
