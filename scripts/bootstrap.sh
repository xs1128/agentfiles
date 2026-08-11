#!/bin/sh
# Installs everything the manifests name into $CLAUDE_CONFIG_DIR. Build-time only.
set -eu

manifests="${1:?usage: bootstrap.sh <manifests-dir>}"
: "${CLAUDE_CONFIG_DIR:?must point at the config dir being assembled}"

jq -r '.packages | to_entries[] | "\(.key)@\(.value.version)"' "$manifests/mcp.json" |
  xargs npm install -g

jq -r '.marketplaces | to_entries[] | "\(.key) \(.value.repo) \(.value.commit)"' "$manifests/plugins.json" |
  while read -r name repo commit; do
    claude plugin marketplace add "$repo"
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
