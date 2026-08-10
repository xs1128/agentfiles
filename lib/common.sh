#!/usr/bin/env bash
# Shared helpers. Sourced, not executed.

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
BACKUP_DIR="${BACKUP_DIR:-$HOME/.agent-config-backups/$(date +%Y%m%d-%H%M%S)}"
DRY_RUN="${DRY_RUN:-0}"
FAILURES=0   # non-fatal problems; the run finishes, then exits non-zero

C_DIM=$'\033[38;5;240m'; C_RED=$'\033[38;5;203m'; C_YEL=$'\033[38;5;220m'
C_GRN=$'\033[38;5;71m'; C_BLD=$'\033[1m'; C_OFF=$'\033[0m'

info()  { [ "${QUIET:-0}" = 1 ] || printf '%s\n' "  $*"; }
step()  { printf '%s\n' "${C_BLD}==>${C_OFF} $*"; }
ok()    { [ "${QUIET:-0}" = 1 ] || printf '%s\n' "  ${C_GRN}ok${C_OFF}    $*"; }
warn()  { printf '%s\n' "  ${C_YEL}warn${C_OFF}  $*" >&2; }
fail()  { printf '%s\n' "  ${C_RED}fail${C_OFF}  $*" >&2; }
die()   { fail "$*"; exit 1; }
skip()  { [ "${QUIET:-0}" = 1 ] || printf '%s\n' "  ${C_DIM}skip${C_OFF}  $*"; }
plan()  { [ "${QUIET:-0}" = 1 ] || printf '%s\n' "  ${C_DIM}would${C_OFF} $*"; }

run() {
  if [ "$DRY_RUN" = "1" ]; then plan "$*"; return 0; fi
  "$@"
}

# Component gate. install.sh and doctor.sh both fill COMPONENTS from their flags.
want() { case " ${COMPONENTS:-} " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

expand_tilde() { printf '%s' "${1/#\~/$HOME}"; }

BACKUP_ROOT="${BACKUP_ROOT:-$HOME/.agent-config-backups}"
BACKUP_KEEP=10

# A target outside $HOME keeps its leading /, which would yield "$BACKUP_DIR//abs"
# and defeat install.sh's `find -path "*/$rel"` dedup.
backup_rel() {
  case "$1" in "$HOME"/*) printf '%s' "${1#"$HOME"/}" ;; *) printf '%s' "${1#/}" ;; esac
}

# Pass the incoming replacement as $2 and a byte-identical target is dropped, not
# archived: that is what stops the tree growing on every idempotent re-run.
backup_path() {
  local target="$1" incoming="${2:-}"
  [ -e "$target" ] || [ -L "$target" ] || return 0
  local dest
  dest="$BACKUP_DIR/$(backup_rel "$target")"
  if [ "$DRY_RUN" = "1" ]; then plan "back up $target -> $dest"; return 0; fi
  if [ -n "$incoming" ] && cmp -s "$target" "$incoming" 2>/dev/null; then
    rm -rf "$target"
    return 0
  fi
  # Its own statement: `mkdir -p -m` only modes the deepest component.
  mkdir -p "$BACKUP_DIR"
  chmod 700 "$BACKUP_ROOT" "$BACKUP_DIR"
  mkdir -p "$(dirname "$dest")"
  mv "$target" "$dest"
  info "backed up $target -> $dest"
}

# Keep the newest BACKUP_KEEP; the timestamped names sort chronologically, so -r is newest-first.
prune_backups() {
  [ -d "$BACKUP_ROOT" ] || return 0
  local dir
  find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d 2>/dev/null \
    | sort -r | tail -n "+$((BACKUP_KEEP + 1))" \
    | while IFS= read -r dir; do rm -rf "$dir"; done
}

# Symlink src -> dst. Already correct: skip. Anything else: back up first.
link() {
  local src="$1" dst="$2"
  src="$(expand_tilde "$src")"; dst="$(expand_tilde "$dst")"
  if [ ! -e "$src" ]; then
    warn "link source missing: $src"
    # Returning non-zero here killed the whole run under `set -e`. A dry run on a
    # fresh machine has no shared skill tree yet, so that case is not a failure.
    [ "$DRY_RUN" = "1" ] || FAILURES=$((FAILURES + 1))
    return 0
  fi

  if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
    skip "$dst (already linked)"
    return 0
  fi
  backup_path "$dst" "$src"
  run mkdir -p "$(dirname "$dst")"
  run ln -s "$src" "$dst"
  [ "$DRY_RUN" = "1" ] || ok "$dst -> $src"
}

# Render ${VAR} from the environment. Fails on unset vars, so a half-filled
# secrets file never becomes an empty API key.
render_template() {
  local tmpl="$1" dst="$2" kind="${3:-config}" missing=()
  tmpl="$(expand_tilde "$tmpl")"; dst="$(expand_tilde "$dst")"
  [ -f "$tmpl" ] || { warn "template missing: $tmpl"; return 1; }

  local var
  while IFS= read -r var; do
    [ -n "${!var:-}" ] || missing+=("$var")
  done < <(grep -oE '\$\{[A-Z_][A-Z0-9_]*\}' "$tmpl" | tr -d '${}' | sort -u)

  if [ ${#missing[@]} -gt 0 ]; then
    warn "$(basename "$tmpl"): unset ${missing[*]}: see $SECRETS_FILE"
    if [ "$kind" = secret ] && { [ -e "$dst" ] || [ -L "$dst" ]; }; then
      if [ "$DRY_RUN" = 1 ]; then plan "remove stale secret config $dst"; else rm -f "$dst"; fi
    fi
    return 1
  fi
  if [ "$DRY_RUN" = "1" ]; then plan "render $tmpl -> $dst"; return 0; fi

  [ "$kind" = secret ] || backup_path "$dst"
  mkdir -p "$(dirname "$dst")"
  local tmp; tmp="$(mktemp "${dst}.tmp.XXXXXX")"
  if ! python3 -c 'import os,sys,string
src=open(sys.argv[1]).read()
open(sys.argv[2],"w").write(string.Template(src).substitute(os.environ))' "$tmpl" "$tmp"; then
    rm -f "$tmp"; return 1
  fi
  chmod 600 "$tmp"
  mv -f "$tmp" "$dst"
  ok "$dst (rendered, chmod 600)"
}

remove_secret_config() {
  [ -e "$1" ] || [ -L "$1" ] || return 0
  if [ "$DRY_RUN" = 1 ]; then plan "remove stale secret config $1"; else rm -f "$1"; ok "removed stale secret config $1"; fi
}

have() { command -v "$1" >/dev/null 2>&1; }

# Read one value from a JSON manifest, no jq needed.
jget() { python3 -c 'import json,sys;d=json.load(open(sys.argv[1]))
for k in sys.argv[2].split("."):
    d = d[k]
print(d)' "$1" "$2"; }
