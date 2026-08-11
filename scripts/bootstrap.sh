#!/bin/sh
# Installs the plugins manifests/plugins.json pins. Safe to rerun.
# Usage: bootstrap.sh [--mcp]   (--mcp also installs the pinned MCP servers)
set -eu

repo="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
manifests="$repo/manifests"
with_mcp=0
for arg in "$@"; do
  case "$arg" in
    --mcp) with_mcp=1 ;;
    *) echo "usage: bootstrap.sh [--mcp]" >&2; exit 2 ;;
  esac
done

export CLAUDE_CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

# Not a pipe into while: a failure inside one aborts the loop silently, exit 0.
marketplaces="$(jq -r '.marketplaces | to_entries[] | "\(.key) \(.value.repo) \(.value.commit)"' "$manifests/plugins.json")"
echo "$marketplaces" | while read -r name repo_url commit; do
  claude plugin marketplace add "$repo_url"
  dir="$CLAUDE_CONFIG_DIR/plugins/marketplaces/$name"

  # An earlier install may have left a directory with no history to pin against.
  if ! git -C "$dir" rev-parse --git-dir >/dev/null 2>&1; then
    echo "re-cloning $name: $dir has no git history"
    rm -rf "$dir"
    git clone -q "https://github.com/$repo_url" "$dir"
  fi

  # Shallow clone, so it rarely contains the pin.
  git -C "$dir" fetch -q origin "$commit" 2>/dev/null || git -C "$dir" fetch -q --unshallow
  git -C "$dir" checkout -q "$commit"
done || exit 1

# Installs read the working tree, so they follow every checkout.
jq -r '.plugins | keys[]' "$manifests/plugins.json" |
  while read -r plugin; do
    claude plugin install "$plugin"
  done

if [ "$with_mcp" -eq 1 ]; then
  # A system node puts its global prefix where only root can write.
  if [ ! -w "$(npm root -g 2>/dev/null || echo /)" ]; then
    npm config set prefix "$HOME/.local"
    echo "npm global prefix moved to $HOME/.local (it was not writable)"
  fi

  # claude/mcp/*.json call these by bare name, so they must be on $PATH.
  jq -r '.packages | to_entries[] | "\(.key)@\(.value.version)"' "$manifests/mcp.json" |
    xargs npm install -g
fi
