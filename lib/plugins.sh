#!/usr/bin/env bash
# Claude plugins from claude/plugins.json. settings.json would fetch these on
# next launch anyway; doing it here makes a fresh machine usable on first run.

PLUGINS_MANIFEST="$REPO_ROOT/claude/plugins.json"

install_plugins() {
  step "Installing Claude plugins"
  have claude || { warn "claude not on PATH — skipping plugins"; return 0; }

  local name repo
  while IFS=$'\t' read -r name repo; do
    [ -n "$name" ] || continue
    if [ "$DRY_RUN" = "1" ]; then
      plan "claude plugin marketplace add $repo"
    else
      claude plugin marketplace add "$repo" >/dev/null 2>&1 \
        && ok "marketplace $name" \
        || skip "marketplace $name (already known)"
    fi
  done < <(python3 -c 'import json,sys
m=json.load(open(sys.argv[1]))
for name,repo in m["marketplaces"].items(): print("\t".join([name,repo]))' "$PLUGINS_MANIFEST")

  local key version
  while IFS=$'\t' read -r key version; do
    [ -n "$key" ] || continue
    if [ "$DRY_RUN" = "1" ]; then
      plan "claude plugin install $key  (pinned $version)"
    else
      claude plugin install "$key" >/dev/null 2>&1 \
        && ok "$key @ $version" \
        || skip "$key (already installed)"
    fi
  done < <(python3 -c 'import json,sys
m=json.load(open(sys.argv[1]))
for key,s in m["plugins"].items(): print("\t".join([key,s["version"]]))' "$PLUGINS_MANIFEST")

  prune_unmanaged_plugins "${CLAUDE_HOME:-$HOME/.claude}"
  [ "$DRY_RUN" = "1" ] || verify_required_plugins "${CLAUDE_HOME:-$HOME/.claude}"
  [ "$DRY_RUN" = "1" ] || verify_plugin_pins "${CLAUDE_HOME:-$HOME/.claude}"
}

# `claude plugin install` takes no version or commit flag — it always fetches
# latest — so plugins.json's pins can be read back but never enforced.
# Reported, not counted: upstream claude-hud ships 0.6.0 against a 0.3.0 pin, so
# counting this would make install.sh exit 1 on every fresh machine forever, and
# the uninstall/reinstall once suggested here only refetches latest again.
verify_plugin_pins() {
  local state="$1/plugins/installed_plugins.json"
  local key detail drifted=0
  while IFS=$'\t' read -r key detail; do
    [ -n "$key" ] || continue
    warn "plugin $key: $detail"
    info "     bump the pin in claude/plugins.json once you have reviewed the upstream diff"
    drifted=1
  done < <(python3 - "$PLUGINS_MANIFEST" "$state" <<'PY'
import json, os, sys
manifest = json.load(open(sys.argv[1]))["plugins"]
installed = {}
if os.path.exists(sys.argv[2]):
    installed = json.load(open(sys.argv[2])).get("plugins", {})
for key, spec in manifest.items():
    entries = installed.get(key) or []
    if not entries:
        continue  # absence is verify_required_plugins' job
    got = entries[0]
    for field, want in (("version", spec.get("version")), ("gitCommitSha", spec.get("commit"))):
        if want and got.get(field) != want:
            print("\t".join([key, "%s is %s, plugins.json pins %s" % (field, got.get(field), want)]))
PY
)
  if [ "$drifted" = 0 ]; then ok "plugin pins match plugins.json"; fi
}

# Dropping a plugin from plugins.json has to actually remove it, or the repo
# stops describing the machine: settings.json would no longer enable it, but its
# skills stay on disk and keep showing up in the skill list.
prune_unmanaged_plugins() {
  local home="$1"
  local state="$home/plugins/installed_plugins.json"
  [ -f "$state" ] || return 0

  local key
  while IFS= read -r key; do
    [ -n "$key" ] || continue
    if [ "$DRY_RUN" = "1" ]; then
      plan "claude plugin uninstall $key  (installed but not in plugins.json)"
    else
      claude plugin uninstall "$key" >/dev/null 2>&1 \
        && ok "uninstalled $key (not in plugins.json)" \
        || warn "could not uninstall $key — remove it with: claude plugin uninstall $key"
    fi
  done < <(python3 - "$PLUGINS_MANIFEST" "$state" <<'PY'
import json, sys
wanted = set(json.load(open(sys.argv[1]))["plugins"])
installed = json.load(open(sys.argv[2])).get("plugins", {})
for key, entries in installed.items():
    if key not in wanted and entries:
        print(key)
PY
)
}

# Plugins marked `"required": true` in plugins.json are load-bearing — the
# statusline and the caveman mode are both plugin-provided. A silent install
# failure would otherwise only surface as a blank statusline later.
verify_required_plugins() {
  local home="$1"
  local state="$home/plugins/installed_plugins.json"
  local missing=()

  while IFS= read -r key; do
    [ -n "$key" ] && missing+=("$key")
  done < <(python3 - "$PLUGINS_MANIFEST" "$state" <<'PY'
import json, os, sys
manifest = json.load(open(sys.argv[1]))
required = [k for k, s in manifest["plugins"].items() if s.get("required")]
installed = {}
if os.path.exists(sys.argv[2]):
    installed = json.load(open(sys.argv[2])).get("plugins", {})
for key in required:
    if not installed.get(key):
        print(key)
PY
)

  if [ ${#missing[@]} -gt 0 ]; then
    fail "required plugin(s) not installed: ${missing[*]}"
    info "     fix: claude plugin install ${missing[0]}"
    # Counted, not returned: returning 1 errexited install.sh before the MCP
    # servers and the entire GLM profile block ever ran.
    FAILURES=$((FAILURES + ${#missing[@]}))
    return 0
  fi
  ok "required plugins present (caveman, claude-hud)"
}
