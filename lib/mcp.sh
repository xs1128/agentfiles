#!/usr/bin/env bash
# MCP servers from claude/mcp.json.
#
# These cannot be symlinked: Claude stores MCP definitions in ~/.claude.json,
# which it also rewrites itself (session state, project trust, tool approvals).
# So the repo holds the desired definitions and the CLI applies them, the same
# copy-in-not-link reasoning as codex/config.toml.

MCP_MANIFEST="$REPO_ROOT/claude/mcp.json"

install_mcp_servers() {
  step "Registering MCP servers"
  have claude || { warn "claude not on PATH — skipping MCP servers"; return 0; }

  local name scope json
  while IFS=$'\t' read -r name scope json; do
    [ -n "$name" ] || continue

    # add-json errors on an existing name rather than updating, so replace it.
    if claude mcp get "$name" >/dev/null 2>&1; then
      if [ "$DRY_RUN" = "1" ]; then
        plan "re-register mcp $name (already present)"
        continue
      fi
      claude mcp remove --scope "$scope" "$name" >/dev/null 2>&1 || true
    elif [ "$DRY_RUN" = "1" ]; then
      plan "claude mcp add-json --scope $scope $name '<config>'"
      continue
    fi

    if claude mcp add-json --scope "$scope" "$name" "$json" >/dev/null 2>&1; then
      ok "mcp $name ($scope scope)"
    else
      fail "mcp $name could not be registered"
      info "     retry by hand: claude mcp add-json --scope $scope $name '$json'"
    fi
  done < <(python3 -c 'import json,sys
m=json.load(open(sys.argv[1]))
for name,s in m["servers"].items():
    print("\t".join([name, s.get("scope","user"), json.dumps(s["config"])]))' "$MCP_MANIFEST")
}
