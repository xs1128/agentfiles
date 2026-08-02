#!/usr/bin/env bash
# Read-only: does this machine still match the repo? Exits non-zero if not.
#
#   ./doctor.sh            all agents
#   ./doctor.sh --claude   one

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$REPO_ROOT/lib/common.sh"
. "$REPO_ROOT/lib/secrets.sh"

CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
PI_HOME="${PI_HOME:-$HOME/.pi/agent}"
SKILLS_MANIFEST="$REPO_ROOT/shared/manifests/skills.json"
WIKI_MANIFEST="$REPO_ROOT/shared/manifests/wiki.json"

PROBLEMS=0
bad() { fail "$*"; PROBLEMS=$((PROBLEMS + 1)); }

check_link() {
  local want="$1" at="$2"
  want="$(expand_tilde "$want")"; at="$(expand_tilde "$at")"
  if [ ! -e "$at" ] && [ ! -L "$at" ]; then bad "missing: $at"; return; fi
  if [ ! -L "$at" ]; then bad "not a link (local edit will be lost on install): $at"; return; fi
  local got; got="$(readlink "$at")"
  [ "$got" = "$want" ] && ok "$at" || bad "$at -> $got (expected $want)"
}

check_dead_links() {
  local dir; dir="$(expand_tilde "$1")"
  [ -d "$dir" ] || return 0
  local dead=() entry
  for entry in "$dir"/*; do
    [ -L "$entry" ] && [ ! -e "$entry" ] && dead+=("$(basename "$entry")")
  done
  if [ ${#dead[@]} -gt 0 ]; then
    bad "$dir: ${#dead[@]} dead link(s): ${dead[*]}"
    info "     fix: ./install.sh (prunes them)"
  else
    ok "$dir: no dead links"
  fi
}

check_skill_count() {
  local dir="$1" expected="$2" label="$3"
  dir="$(expand_tilde "$dir")"
  [ -d "$dir" ] || { bad "$dir missing"; return; }
  local actual; actual="$(find "$dir" -maxdepth 1 -mindepth 1 | wc -l | tr -d ' ')"
  if [ "$actual" -lt "$expected" ]; then
    bad "$label: $actual present, manifest expects at least $expected"
  else
    ok "$label: $actual skills"
  fi
}

# Claude and Codex both take the third-party and wiki populations; pi takes only
# the former. shared/skills/ is not counted — check_skill_count is a floor.
third_party_and_wiki_count() {
  python3 -c 'import json,sys
a=len(json.load(open(sys.argv[1]))["skills"]);b=len(json.load(open(sys.argv[2]))["skills"]);print(a+b)' \
    "$SKILLS_MANIFEST" "$WIKI_MANIFEST"
}

DO_CLAUDE=0; DO_CODEX=0; DO_PI=0
if [ $# -eq 0 ]; then DO_CLAUDE=1; DO_CODEX=1; DO_PI=1; fi
for arg in "$@"; do
  case "$arg" in
    --claude) DO_CLAUDE=1 ;; --codex) DO_CODEX=1 ;; --pi) DO_PI=1 ;;
    --all) DO_CLAUDE=1; DO_CODEX=1; DO_PI=1 ;;
    -h|--help) sed -n '2,5p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown flag: $arg" ;;
  esac
done

printf '%s\n\n' "${C_BLD}agent-config doctor${C_OFF} ${C_DIM}$REPO_ROOT${C_OFF}"

step "Repo"
if git -C "$REPO_ROOT" diff --quiet 2>/dev/null; then
  ok "clean working tree"
else
  warn "uncommitted changes in repo ($(git -C "$REPO_ROOT" status --porcelain | wc -l | tr -d ' ') file(s))"
fi

step "Secrets"
if [ -f "$SECRETS_FILE" ]; then
  mode="$(stat -f '%Lp' "$SECRETS_FILE" 2>/dev/null || stat -c '%a' "$SECRETS_FILE")"
  [ "$mode" = "600" ] && ok "$SECRETS_FILE (600)" || bad "$SECRETS_FILE is mode $mode, want 600"
  ZAI_API_KEY="$(secret_value "$SECRETS_FILE" ZAI_API_KEY)"
  [ -n "$ZAI_API_KEY" ] && ok "ZAI_API_KEY set" || warn "ZAI_API_KEY unset"
else
  warn "$SECRETS_FILE absent — run ./install.sh to scaffold it"
fi

step "No secrets in repo"
if git -C "$REPO_ROOT" grep -nIE '(sk-[A-Za-z0-9]{20,}|[0-9a-f]{32}\.[A-Za-z0-9]{16,})' -- . >/dev/null 2>&1; then
  bad "possible credential committed — inspect: git grep -nIE '(sk-[A-Za-z0-9]{20,}|[0-9a-f]{32}\\.[A-Za-z0-9]{16,})'"
else
  ok "no API-key-shaped strings tracked"
fi

if [ "$DO_CLAUDE" = 1 ]; then
  step "Claude Code"
  for pair in "agents:agents" "workflows:workflows" "CLAUDE.md:CLAUDE.md" "RTK.md:RTK.md" \
              "settings.json:settings.json" "statusline.sh:statusline.sh" \
              "hud-statusline.sh:hud-statusline.sh"; do
    check_link "$REPO_ROOT/claude/${pair%%:*}" "$CLAUDE_HOME/${pair##*:}"
  done
  check_dead_links "$CLAUDE_HOME/skills"
  check_skill_count "$CLAUDE_HOME/skills" "$(third_party_and_wiki_count)" "claude skills"
  # The three mandatory pieces: rtk (host binary), caveman + claude-hud (plugins).
  have rtk || bad "rtk missing — the Bash PreToolUse hook in settings.json will fail on every call"
  have bun || bad "bun missing — claude-hud statusline will not render"
  have jq  || bad "jq missing — claude/statusline.sh degrades to a bare model name"

  # MCP servers live in ~/.claude.json, which Claude rewrites; ask the CLI.
  if have claude; then
    while IFS= read -r server; do
      [ -n "$server" ] || continue
      claude mcp get "$server" >/dev/null 2>&1 \
        && ok "mcp $server registered" \
        || bad "mcp $server not registered — run ./install.sh --claude"
    done < <(python3 -c 'import json,sys;print("\n".join(json.load(open(sys.argv[1]))["servers"]))' \
               "$REPO_ROOT/claude/mcp.json")
  fi

  while IFS=$'\t' read -r status key note; do
    [ -n "$key" ] || continue
    [ "$status" = ok ] && ok "plugin $key ($note)" || bad "plugin $key missing — $note"
  done < <(python3 - "$REPO_ROOT/claude/plugins.json" "$CLAUDE_HOME/plugins/installed_plugins.json" <<'PY'
import json, os, sys
manifest = json.load(open(sys.argv[1]))
installed = {}
if os.path.exists(sys.argv[2]):
    installed = json.load(open(sys.argv[2])).get("plugins", {})
for key, spec in manifest["plugins"].items():
    if not spec.get("required"):
        continue
    entries = installed.get(key) or []
    have = entries[0].get("version") if entries else None
    want = spec["version"]
    if have == want:
        print("\t".join(["ok", key, want]))
    elif have:
        print("\t".join(["ok", key, f"{have}, manifest pins {want}"]))
    else:
        print("\t".join(["bad", key, spec.get("why", "required")]))
PY
)
fi

if [ "$DO_CODEX" = 1 ]; then
  step "Codex"
  check_link "$REPO_ROOT/codex/AGENTS.md" "$CODEX_HOME/AGENTS.md"
  check_dead_links "$CODEX_HOME/skills"
  check_skill_count "$CODEX_HOME/skills" "$(third_party_and_wiki_count)" "codex skills"

  # AGENTS.md is the only thing telling Codex to use rtk — it gets no hook.
  have rtk || bad "rtk missing — codex/AGENTS.md tells the model to prefix every shell command with it"

  # Codex ignores `@file` imports (it inlines AGENTS.md verbatim), so the rules
  # only work if they are in the file itself. Ask Codex what it actually sees.
  if have codex; then
    if codex debug prompt-input 2>/dev/null | grep -q 'rtk gain'; then
      ok "rtk instructions reach the model prompt"
    else
      bad "codex/AGENTS.md is not reaching the model prompt — run ./install.sh --codex"
    fi
  fi

  if [ -f "$CODEX_HOME/config.toml" ]; then
    if python3 "$REPO_ROOT/lib/toml_merge.py" "$REPO_ROOT/codex/config.toml.tmpl" \
         "$CODEX_HOME/config.toml" --dry-run | grep -q "already matches"; then
      ok "config.toml carries all managed keys"
    else
      bad "config.toml has drifted from managed keys — run ./install.sh --codex"
    fi
  else
    bad "$CODEX_HOME/config.toml missing"
  fi
fi

if [ "$DO_PI" = 1 ]; then
  step "pi"
  check_link "$REPO_ROOT/pi/settings.json" "$PI_HOME/settings.json"
  if [ -f "$PI_HOME/models.json" ]; then
    mode="$(stat -f '%Lp' "$PI_HOME/models.json" 2>/dev/null || stat -c '%a' "$PI_HOME/models.json")"
    [ "$mode" = "600" ] && ok "models.json (600)" || bad "models.json is mode $mode, want 600 — it holds your z.ai key"
    [ -L "$PI_HOME/models.json" ] && bad "models.json is a symlink into the repo — it holds a secret and must be a rendered local file"
  else
    bad "$PI_HOME/models.json missing — run ./install.sh --pi"
  fi
  check_dead_links "$PI_HOME/skills"
  check_skill_count "$PI_HOME/skills" \
    "$(python3 -c 'import json,sys;print(len(json.load(open(sys.argv[1]))["skills"]))' "$SKILLS_MANIFEST")" \
    "pi skills"
fi

echo
if [ "$PROBLEMS" -eq 0 ]; then
  printf '%s\n' "${C_GRN}healthy${C_OFF} — machine matches repo"
else
  printf '%s\n' "${C_RED}$PROBLEMS problem(s)${C_OFF} — most are fixed by ./install.sh --all"
  exit 1
fi
