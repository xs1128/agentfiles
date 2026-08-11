#!/bin/sh
# Runs Claude Code against z.ai's GLM instead of Anthropic. Installed as claude-glm.
set -eu

# Read the key rather than sourcing the file: an env file is not a shell script,
# and an unquoted value with a space in it would run as a command.
if [ -z "${ZAI_API_KEY:-}" ] && [ -f "$HOME/.agent.env" ]; then
  ZAI_API_KEY="$(sed -n 's/^ZAI_API_KEY=//p' "$HOME/.agent.env" | head -1)"
fi

export ANTHROPIC_BASE_URL=https://api.z.ai/api/anthropic
export ANTHROPIC_AUTH_TOKEN="${ZAI_API_KEY:?set ZAI_API_KEY, or put it in ~/.agent.env}"
export ANTHROPIC_DEFAULT_OPUS_MODEL=glm-5.2
export ANTHROPIC_DEFAULT_SONNET_MODEL=glm-5-turbo
export ANTHROPIC_DEFAULT_HAIKU_MODEL=glm-4.7

# settings.json pins opus[1m], which would otherwise win over the aliases above.
exec claude --model glm-5.2 "$@"
