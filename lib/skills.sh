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
  local dirty; dirty="$(git -C "$dir" status --porcelain 2>/dev/null || true)"
  if [ -n "$dirty" ]; then
    warn "$3: clone cache modified locally — restore with: git -C $dir checkout --force --detach $commit"
  fi
  ok "$3 @ ${commit:0:12}"
}

install_third_party_skills() {
  step "Installing third-party skills (pinned)"
  local root; root="$(expand_tilde "$(jget "$SKILLS_MANIFEST" installRoot)")"

  local slug url commit failed_sources=" "
  while IFS=$'\t' read -r slug url commit; do
    _ensure_source "$url" "$commit" "$slug" \
      || { FAILURES=$((FAILURES + 1)); failed_sources="$failed_sources$slug "; continue; }
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

    # A failed checkout leaves HEAD elsewhere, where both guards below still pass.
    case "$failed_sources" in
      *" ${src//\//__} "*) warn "$name: $src is not at its pinned commit — skipped"; continue ;;
    esac

    [ -d "$from" ] || { warn "$name: $path not present in $src at pinned commit"; continue; }

    # Hash "$commit:$path", not "HEAD:$path", so a stale worktree cannot satisfy it.
    # --verify, or an unresolvable spec is echoed back and reads as a hash mismatch.
    # `|| true`: a bare assignment takes the substitution's status; rev-parse exits 128.
    local got; got="$(git -C "$dir" rev-parse --verify "$commit:$path" 2>/dev/null || true)"
    if [ "$got" != "$want" ]; then
      warn "$name: tree $got does not match folderHash $want — skipped"
      FAILURES=$((FAILURES + 1))
      continue
    fi

    # Untracked files live in no tree, so folderHash cannot see them.
    if [ -n "$(git -C "$dir" status --porcelain -- "$path" 2>/dev/null)" ]; then
      warn "$name: worktree differs from the pinned tree — skipped"
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
    # Counted, not returned: this repo needs credentials a fresh machine has not
    # got yet, and it sits upstream of every agent in install.sh.
    run git clone --quiet -- "$repo" "$checkout" \
      || { fail "clone failed: $repo"; FAILURES=$((FAILURES + 1)); return 0; }
    ok "cloned $repo -> $checkout"
  else
    # Actively edited: never reset it, just report drift.
    # `|| true`: under pipefail a failing `git status` would abort the run here.
    local dirty; dirty="$(git -C "$checkout" status --porcelain 2>/dev/null | wc -l | tr -d ' ' || true)"
    ok "$checkout present${dirty:+ ($dirty uncommitted file(s))}"

    # --verify, or an unborn HEAD echoes the literal "HEAD" back and the warning
    # below reads as though the checkout were fine.
    local head want at
    head="$(git -C "$checkout" rev-parse --verify HEAD 2>/dev/null || true)"
    want="$(jget "$WIKI_MANIFEST" commit || true)"
    if [ "$head" != "$want" ]; then
      at="${head:0:12}"
      warn "$checkout is at ${at:-no commits yet}, wiki.json pins ${want:0:12} — bump the pin once you are happy with it"
    fi
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

# Exact, recoverable reconciliation. Dot-directories remain agent-owned.
reconcile_skill_links() {
  local dir="$1"; shift
  dir="$(expand_tilde "$dir")"
  [ -d "$dir" ] || return 0
  local expected entry name removed=0
  expected="$(python3 - "$SKILLS_MANIFEST" "$WIKI_MANIFEST" "$REPO_ROOT" "$dir" "$@" <<'PY'
import json, os, sys
s, w, repo, dest, *extra = sys.argv[1:]
names = set(json.load(open(s))["skills"]) | set(extra)
wiki = json.load(open(w))
if dest in [os.path.expanduser(p) for p in wiki["linkInto"]]: names |= set(wiki["skills"])
shared = os.path.join(repo, "shared", "skills")
names |= {n for n in os.listdir(shared) if os.path.isdir(os.path.join(shared, n))}
print("\n".join(sorted(names)))
PY
)"
  for entry in "$dir"/*; do
    [ -e "$entry" ] || [ -L "$entry" ] || continue
    name="$(basename "$entry")"
    printf '%s\n' "$expected" | grep -Fxq "$name" && continue
    backup_path "$entry"
    info "removed unmanaged skill $name"
    removed=$((removed + 1))
  done
  prune_dead_links "$dir"
  [ "$removed" -eq 0 ] && skip "$dir (exact skill set)"
}
