#!/usr/bin/env bash
# Three skill populations, one pattern: install once, symlink into every agent.
#   third-party  skills.json -> ~/.agents/skills, from pinned clones
#   wiki         wiki.json   -> live xs-llm-wiki checkout
#   own          shared/skills/, straight from this repo

SKILLS_MANIFEST="$REPO_ROOT/shared/manifests/skills.json"
WIKI_MANIFEST="$REPO_ROOT/shared/manifests/wiki.json"
CLONE_CACHE="$HOME/.cache/agent-config/sources"

# Manifest values are validated, not trusted: a url reaches `git clone`, where
# `ext::sh -c '…'` is remote-code-execution and a leading `-` is read as a flag;
# a name reaches `rm -rf "$root/$name"`, where `../` escapes installRoot.
_safe_name() {
  case "$1" in ""|.*|*[!A-Za-z0-9._-]*) return 1 ;; esac
}

_safe_path() {
  case "$1" in ""|/*|*/|*//*|.*|*/.*|*[!A-Za-z0-9._/-]*) return 1 ;; esac
}

_safe_url() {
  case "$1" in https://*) return 0 ;; *) return 1 ;; esac
}

# Clone or reuse a source repo, hard-pinned to a commit.
_ensure_source() {
  local url="$1" commit="$2" dir="$CLONE_CACHE/$3"

  _safe_name "$3" || { warn "skills.json: refusing unsafe source name: $3"; return 1; }
  _safe_url "$url" || { warn "skills.json: refusing $3, url is not https://: $url"; return 1; }

  if [ ! -d "$dir/.git" ]; then
    run mkdir -p "$(dirname "$dir")"
    run git clone --quiet -- "$url" "$dir" || { fail "clone failed: $url"; return 1; }
  fi
  [ "$DRY_RUN" = "1" ] && { plan "pin $3 -> ${commit:0:12}"; return 0; }

  if [ "$(git -C "$dir" rev-parse HEAD 2>/dev/null)" != "$commit" ]; then
    git -C "$dir" fetch --quiet origin || warn "fetch failed for $3, using local objects"
    git -C "$dir" checkout --quiet --detach "$commit" || { fail "commit $commit not found in $3"; return 1; }
  fi

  # A clone already sitting on $commit skips the checkout above, so without this
  # nothing would ever notice edits made straight into the cache.
  local dirty; dirty="$(git -C "$dir" status --porcelain 2>/dev/null)"
  if [ -n "$dirty" ]; then
    warn "$3: clone cache modified locally — restore with: git -C $dir checkout --force --detach $commit"
  fi
  ok "$3 @ ${commit:0:12}"
}

install_third_party_skills() {
  step "Installing third-party skills (pinned)"
  local root; root="$(expand_tilde "$(jget "$SKILLS_MANIFEST" installRoot)")"

  local slug url commit
  while IFS=$'\t' read -r slug url commit; do
    _ensure_source "$url" "$commit" "$slug" || { FAILURES=$((FAILURES + 1)); continue; }
  done < <(python3 -c 'import json,sys
m=json.load(open(sys.argv[1]))
for name,s in m["sources"].items():
    print("\t".join([name.replace("/","__"), s["url"], s["commit"]]))' "$SKILLS_MANIFEST")

  run mkdir -p "$root"
  local count=0 name src path want commit
  while IFS=$'\t' read -r name src path want commit; do
    if ! _safe_name "$name" || ! _safe_path "$path"; then
      warn "skills.json: refusing unsafe entry (name=$name path=$path)"
      FAILURES=$((FAILURES + 1))
      continue
    fi
    local dir="$CLONE_CACHE/${src//\//__}"
    local from="$dir/$path"
    local to="$root/$name"
    if [ "$DRY_RUN" = "1" ]; then
      count=$((count + 1)); continue
    fi
    [ -d "$from" ] || { warn "$name: $path not present in $src at pinned commit"; continue; }

    # Hash "$commit:$path", not "HEAD:$path": if the checkout above failed this
    # would otherwise verify whatever tree the clone happens to be sitting on.
    local got; got="$(git -C "$dir" rev-parse "$commit:$path" 2>/dev/null)"
    if [ "$got" != "$want" ]; then
      warn "$name: tree $got does not match folderHash $want — skipped"
      FAILURES=$((FAILURES + 1))
      continue
    fi

    # An empty installRoot from a malformed manifest would make this `rm -rf /$name`.
    if [ -z "$root" ] || [ -z "$name" ]; then
      warn "skills.json: empty installRoot or name — refusing to remove $to"
      FAILURES=$((FAILURES + 1))
      continue
    fi
    rm -rf "$to"
    cp -R "$from" "$to"
    count=$((count + 1))
  done < <(python3 -c 'import json,sys
m=json.load(open(sys.argv[1]))
for name,s in m["skills"].items():
    print("\t".join([name, s["source"], s["path"], s["folderHash"], m["sources"][s["source"]]["commit"]]))' "$SKILLS_MANIFEST")

  if [ "$DRY_RUN" = "1" ]; then plan "copy $count skills into $root"; else ok "$count skills in $root"; fi
}

install_wiki_skills() {
  step "Installing wiki skills"
  local checkout repo
  checkout="$(expand_tilde "$(jget "$WIKI_MANIFEST" checkout)")"
  repo="$(jget "$WIKI_MANIFEST" repo)"

  _safe_url "$repo" || { warn "wiki.json: refusing repo, not https://: $repo"; return 0; }

  if [ ! -d "$checkout/.git" ]; then
    run git clone --quiet -- "$repo" "$checkout" || { fail "clone failed: $repo"; return 1; }
    ok "cloned $repo -> $checkout"
  else
    # Actively edited: never reset it, just report drift.
    local dirty; dirty="$(git -C "$checkout" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
    ok "$checkout present${dirty:+ ($dirty uncommitted file(s))}"
  fi
}

# link_skills <agent-skills-dir>: link all three populations into one agent.
link_skills() {
  local dest="$1"
  local root; root="$(expand_tilde "$(jget "$SKILLS_MANIFEST" installRoot)")"
  local wiki; wiki="$(expand_tilde "$(jget "$WIKI_MANIFEST" checkout)")"
  local subdir; subdir="$(jget "$WIKI_MANIFEST" skillsSubdir)"

  run mkdir -p "$(expand_tilde "$dest")"

  local name
  while IFS= read -r name; do
    link "$root/$name" "$dest/$name"
  done < <(python3 -c 'import json,sys;print("\n".join(json.load(open(sys.argv[1]))["skills"]))' "$SKILLS_MANIFEST")

  # Claude and Codex today, not pi; wiki.json's linkInto decides.
  if python3 -c 'import json,sys;sys.exit(0 if sys.argv[2] in [p.replace("~",__import__("os").path.expanduser("~")) for p in json.load(open(sys.argv[1]))["linkInto"]] else 1)' \
       "$WIKI_MANIFEST" "$(expand_tilde "$dest")"; then
    while IFS= read -r name; do
      link "$wiki/$subdir/$name" "$dest/$name"
    done < <(python3 -c 'import json,sys;print("\n".join(json.load(open(sys.argv[1]))["skills"]))' "$WIKI_MANIFEST")
  fi

  for name in "$REPO_ROOT"/shared/skills/*/; do
    name="${name%/}"   # a trailing slash would end up baked into the symlink
    [ -d "$name" ] || continue
    link "$name" "$dest/$(basename "$name")"
  done
}

# Dead links accumulate when a source repo is deleted (~/Desktop/Slides is the
# standing example) and leave agents advertising skills that cannot load.
prune_dead_links() {
  local dir; dir="$(expand_tilde "$1")"
  [ -d "$dir" ] || return 0
  local pruned=0 entry
  for entry in "$dir"/*; do
    if [ -L "$entry" ] && [ ! -e "$entry" ]; then
      if [ "$DRY_RUN" = "1" ]; then
        plan "prune dead link $(basename "$entry") -> $(readlink "$entry")"
      else
        rm "$entry"
        info "pruned dead link $(basename "$entry")"
      fi
      pruned=$((pruned + 1))
    fi
  done
  [ "$pruned" -eq 0 ] && skip "$dir (no dead links)" || ok "$dir: $pruned dead link(s)"
}
