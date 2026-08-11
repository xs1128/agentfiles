#!/bin/sh
# Installs the MCP servers and plugins the manifests pin, into the config dir
# link.sh just populated. Safe to rerun: every step is idempotent.
set -eu

repo="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
manifests="${1:-$repo/manifests}"
export CLAUDE_CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

jq -r '.packages | to_entries[] | "\(.key)@\(.value.version)"' "$manifests/mcp.json" |
  xargs npm install -g

jq -r '.marketplaces | to_entries[] | "\(.key) \(.value.repo) \(.value.commit)"' "$manifests/plugins.json" |
  while read -r name repo_url commit; do
    claude plugin marketplace add "$repo_url"
    # The marketplace arrives as a shallow clone, which rarely contains the pin.
    dir="$CLAUDE_CONFIG_DIR/plugins/marketplaces/$name"
    git -C "$dir" fetch -q origin "$commit" 2>/dev/null || git -C "$dir" fetch -q --unshallow
    git -C "$dir" checkout -q "$commit"
  done

# Installs read the marketplace working tree, so they must follow every checkout.
jq -r '.plugins | keys[]' "$manifests/plugins.json" |
  while read -r plugin; do
    claude plugin install "$plugin"
  done
