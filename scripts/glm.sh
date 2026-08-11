#!/bin/sh
# Runs Claude Code against z.ai's GLM. Installed as glm.
set -eu

# Read, not source: an unquoted value with a space would run as a command.
if [ -z "${ZAI_API_KEY:-}" ] && [ -f "$HOME/.agent.env" ]; then
  ZAI_API_KEY="$(sed -n 's/^ZAI_API_KEY=//p' "$HOME/.agent.env" | head -1)"
fi

export ANTHROPIC_BASE_URL=https://api.z.ai/api/anthropic
export ANTHROPIC_AUTH_TOKEN="${ZAI_API_KEY:?set ZAI_API_KEY, or put it in ~/.agent.env}"
export ANTHROPIC_DEFAULT_OPUS_MODEL=glm-5.2
export ANTHROPIC_DEFAULT_SONNET_MODEL=glm-5-turbo
export ANTHROPIC_DEFAULT_HAIKU_MODEL=glm-4.7

# settings.json pins opus[1m], which would win over the aliases above.
exec claude --model glm-5.2 "$@"
