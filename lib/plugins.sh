#!/usr/bin/env bash
# Claude plugins from claude/plugins.json. settings.json would fetch these on
# next launch anyway; doing it here makes a fresh machine usable on first run.

PLUGINS_MANIFEST="$REPO_ROOT/claude/plugins.json"

install_plugins() {
  step "Installing Claude plugins"
  have claude || { warn "claude not on PATH: skipping plugins"; return 0; }

  local name repo commit dir known
  known="$(claude plugin marketplace list 2>/dev/null || true)"
  while IFS=$'\t' read -r name repo commit; do
    [ -n "$name" ] || continue
    dir="$CLONE_CACHE/plugin-$name"
    [ "$name" != claude-plugins-official ] || dir="$CLAUDE_HOME/plugins/marketplaces/$name"
    if [ "$DRY_RUN" = "1" ]; then
      plan "pin marketplace $name -> ${commit:0:12}"
    elif [ "$(git -C "$dir" rev-parse HEAD 2>/dev/null)" = "$commit" ] &&
         printf '%s' "$known" | grep -qE "(^|[^a-z0-9_-])$name($|[^a-z0-9_-])"; then
      # Already registered at the pin: re-adding it would churn for nothing.
      skip "marketplace $name @ ${commit:0:12}"
    else
      claude plugin marketplace remove "$name" >/dev/null 2>&1 || true
      if [ "$name" = claude-plugins-official ]; then
        claude plugin marketplace add "$repo" >/dev/null 2>&1 || { fail "marketplace $name"; FAILURES=$((FAILURES + 1)); continue; }
        git -C "$dir" fetch --quiet origin "$commit" || true
        git -C "$dir" checkout --quiet --detach "$commit" || { fail "cannot pin $name"; FAILURES=$((FAILURES + 1)); continue; }
      else
        _ensure_source "https://github.com/$repo.git" "$commit" "plugin-$name" || {
          FAILURES=$((FAILURES + 1)); continue;
        }
        if [ -n "$(git -C "$dir" status --porcelain)" ]; then
          fail "marketplace $name cache is modified"
          FAILURES=$((FAILURES + 1)); continue
        fi
        claude plugin marketplace add "$dir" >/dev/null 2>&1 || { fail "marketplace $name"; FAILURES=$((FAILURES + 1)); continue; }
      fi
      ok "marketplace $name @ ${commit:0:12}"
    fi
  done < <(python3 -c 'import json,sys
m=json.load(open(sys.argv[1]))
for name,s in m["marketplaces"].items(): print("\t".join([name,s["repo"],s["commit"]]))' "$PLUGINS_MANIFEST")

  local key version pin state="$CLAUDE_HOME/plugins/installed_plugins.json"
  while IFS=$'\t' read -r key version pin; do
    [ -n "$key" ] || continue
    if [ "$DRY_RUN" = "1" ]; then
      plan "claude plugin install $key  (pinned $version)"
    else
      if python3 - "$state" "$key" "$version" "$pin" <<'PY'
import json, os, sys
path, key, version, commit = sys.argv[1:]
data = json.load(open(path)).get("plugins", {}) if os.path.exists(path) else {}
rows = data.get(key) or []
ok = rows and rows[0].get("version") == version and (not commit or rows[0].get("gitCommitSha") == commit)
raise SystemExit(0 if ok else 1)
PY
      then
        skip "$key @ $version"
        continue
      fi
      claude plugin uninstall "$key" >/dev/null 2>&1 || true
      claude plugin install "$key" >/dev/null 2>&1 \
        && ok "$key @ $version" \
        || { fail "$key could not be installed"; FAILURES=$((FAILURES + 1)); }
    fi
  done < <(python3 -c 'import json,sys
m=json.load(open(sys.argv[1]))
for key,s in m["plugins"].items(): print("\t".join([key,s["version"],s.get("commit", "")]))' "$PLUGINS_MANIFEST")

  prune_unmanaged_plugins "${CLAUDE_HOME:-$HOME/.claude}"
  [ "$DRY_RUN" = "1" ] || verify_required_plugins "${CLAUDE_HOME:-$HOME/.claude}"
  [ "$DRY_RUN" = "1" ] || verify_plugin_pins "${CLAUDE_HOME:-$HOME/.claude}"
  [ "$DRY_RUN" = "1" ] || restore_marketplace_declarations "${CLAUDE_HOME:-$HOME/.claude}"
}

# settings.json is symlinked into the repo, so this writes a tracked file,
# only ever when a marketplace is genuinely missing from it.
restore_marketplace_declarations() {
  python3 - "$PLUGINS_MANIFEST" "$1/settings.json" <<'PY'
import json, os, sys, tempfile
manifest, path = json.load(open(sys.argv[1])), os.path.realpath(sys.argv[2])
data = json.load(open(path))
before = json.dumps(data, sort_keys=True)
for name, spec in manifest["marketplaces"].items():
    data.setdefault("extraKnownMarketplaces", {})[name] = {
        "source": {"source": "github", "repo": spec["repo"]}}
if json.dumps(data, sort_keys=True) == before:
    raise SystemExit(0)
with tempfile.NamedTemporaryFile("w", dir=os.path.dirname(path), delete=False) as f:
    json.dump(data, f, indent=2); f.write("\n"); tmp = f.name
os.replace(tmp, path)
PY
}

# Marketplace checkouts make these pins enforceable on fresh installs.
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
# Keep apostrophes out of these heredocs: bash 3.2 fails to find the closing
# paren of the enclosing <( ) and aborts at runtime. `bash -n` does not catch it.
manifest = json.load(open(sys.argv[1]))["plugins"]
installed = {}
if os.path.exists(sys.argv[2]):
    installed = json.load(open(sys.argv[2])).get("plugins", {})
for key, spec in manifest.items():
    entries = installed.get(key) or []
    if not entries:
        continue  # absence is handled by verify_required_plugins
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
        || warn "could not uninstall $key: remove it with: claude plugin uninstall $key"
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

# Plugins marked `"required": true` in plugins.json are load-bearing: the
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
