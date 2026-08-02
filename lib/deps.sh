#!/usr/bin/env bash
# Host dependency checks from shared/manifests/deps.json.
# Reports what is missing; never installs anything silently.

DEPS_MANIFEST="$REPO_ROOT/shared/manifests/deps.json"
DEPS_MISSING=0

# deps.json's "check" runs where bare PATH presence cannot tell two binaries of
# the same name apart — see rtk. Trusted input: the manifest is a repo file.
_dep_present() {
  local name="$1" check="$2"
  # Not under --dry-run: these are real subprocesses that write state — `rtk gain`
  # creates history.db, `go version` a telemetry dir — and a dry run changes nothing.
  if [ -n "$check" ] && [ "$DRY_RUN" != "1" ]; then
    eval "$check" >/dev/null 2>&1
  else
    have "$name"
  fi
}

_dep_check() {
  local name="$1" install_hint="$2" why="$3" check="${4:-}"
  if _dep_present "$name" "$check"; then
    ok "$name"
  else
    DEPS_MISSING=$((DEPS_MISSING + 1))
    fail "$name missing${why:+ — $why}"
    info "     install: $install_hint"
  fi
}

# Emits "name<TAB>install<TAB>why<TAB>check" per group.
_dep_rows() {
  python3 - "$DEPS_MANIFEST" "$1" <<'PY'
import json, sys
manifest, group = json.load(open(sys.argv[1])), sys.argv[2]
node = manifest
for key in group.split("."):
    node = node.get(key, {})
for name, spec in node.items():
    print("\t".join([name, spec.get("install", "?"), spec.get("why", ""), spec.get("check", "")]))
PY
}

check_deps() {
  local agents=("$@")
  step "Checking host dependencies"

  local name hint why check
  while IFS=$'\t' read -r name hint why check; do
    [ -n "$name" ] && _dep_check "$name" "$hint" "$why" "$check"
  done < <(_dep_rows required)

  local agent
  for agent in "${agents[@]}"; do
    while IFS=$'\t' read -r name hint why check; do
      [ -n "$name" ] && _dep_check "$name" "$hint" "$why" "$check"
    done < <(_dep_rows "perAgent.$agent")
  done

  while IFS=$'\t' read -r name hint why check; do
    if [ -n "$name" ]; then
      _dep_present "$name" "$check" && ok "$name (optional)" || warn "$name missing (optional)${why:+ — $why}"
    fi
  done < <(_dep_rows optional)

  if [ "$DEPS_MISSING" -gt 0 ]; then
    die "$DEPS_MISSING required dependency(s) missing — install them, then re-run"
  fi
}
