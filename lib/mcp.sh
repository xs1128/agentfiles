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

  local name scope state json
  while IFS=$'\t' read -r name scope state json; do
    [ -n "$name" ] || continue

    if [ "$state" = same ]; then
      skip "mcp $name (already registered as configured)"
      continue
    fi

    if [ "$DRY_RUN" = "1" ]; then
      if [ "$state" = differ ]; then
        plan "re-register mcp $name (registered definition differs)"
      else
        plan "claude mcp add-json --scope $scope $name '<config>'"
      fi
      continue
    fi

    # add-json errors on an existing name rather than updating, so replace it.
    # Only when it genuinely differs: an unconditional remove leaves a working
    # server deregistered if the add that follows fails.
    if [ "$state" = differ ]; then
      claude mcp remove --scope "$scope" "$name" >/dev/null 2>&1 || true
    fi

    if claude mcp add-json --scope "$scope" "$name" "$json" >/dev/null 2>&1; then
      ok "mcp $name ($scope scope)"
    else
      fail "mcp $name could not be registered"
      info "     retry by hand: claude mcp add-json --scope $scope $name '$json'"
      FAILURES=$((FAILURES + 1))
    fi
  done < <(python3 - "$MCP_MANIFEST" "$HOME/.claude.json" <<'PY'
import json, os, sys
# `claude mcp get` has no --json, so compare against the user-scope store itself.
manifest = json.load(open(sys.argv[1]))["servers"]
registered = {}
if os.path.exists(sys.argv[2]):
    registered = json.load(open(sys.argv[2])).get("mcpServers") or {}
for name, spec in manifest.items():
    want = spec["config"]
    have = registered.get(name)
    state = "same" if have == want else ("differ" if have else "absent")
    print("\t".join([name, spec.get("scope", "user"), state, json.dumps(want)]))
PY
)
}
