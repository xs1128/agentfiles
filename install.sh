#!/usr/bin/env bash
# agent-config installer. Idempotent; anything in the way is backed up first.
#
#   ./install.sh --all
#   ./install.sh --claude --codex
#   ./install.sh --all --dry-run          print every action, change nothing
#   ./install.sh --claude --profile glm

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$REPO_ROOT/lib/common.sh"
. "$REPO_ROOT/lib/secrets.sh"
. "$REPO_ROOT/lib/deps.sh"
. "$REPO_ROOT/lib/skills.sh"
. "$REPO_ROOT/lib/plugins.sh"
. "$REPO_ROOT/lib/mcp.sh"

CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
PI_HOME="${PI_HOME:-$HOME/.pi/agent}"
GLM_HOME="${GLM_HOME:-$HOME/.claude-glm}"

DO_CLAUDE=0; DO_CODEX=0; DO_PI=0; PROFILE="native"

usage() {
  sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --all)     DO_CLAUDE=1; DO_CODEX=1; DO_PI=1 ;;
    --claude)  DO_CLAUDE=1 ;;
    --codex)   DO_CODEX=1 ;;
    --pi)      DO_PI=1 ;;
    --profile) PROFILE="${2:?--profile needs a value}"; shift ;;
    --dry-run) DRY_RUN=1 ;;
    -h|--help) usage 0 ;;
    *) die "unknown flag: $1 (try --help)" ;;
  esac
  shift
done

[ $((DO_CLAUDE + DO_CODEX + DO_PI)) -gt 0 ] || usage 2

AGENTS=()
[ "$DO_CLAUDE" = 1 ] && AGENTS+=(claude)
[ "$DO_CODEX"  = 1 ] && AGENTS+=(codex)
[ "$DO_PI"     = 1 ] && AGENTS+=(pi)

printf '%s\n' "${C_BLD}agent-config${C_OFF} ${C_DIM}$REPO_ROOT${C_OFF}"
printf '%s\n' "  agents: ${AGENTS[*]}   profile: $PROFILE"
[ "$DRY_RUN" = "1" ] && printf '%s\n' "  ${C_YEL}dry run — nothing will be modified${C_OFF}"
echo

check_deps "${AGENTS[@]}"
echo
scaffold_secrets
echo

# Shared skill tree: installed once, linked into every agent.
install_third_party_skills
echo
install_wiki_skills
echo

install_claude() {
  step "Claude Code -> $CLAUDE_HOME"
  run mkdir -p "$CLAUDE_HOME"

  link "$REPO_ROOT/claude/agents"        "$CLAUDE_HOME/agents"
  link "$REPO_ROOT/claude/workflows"     "$CLAUDE_HOME/workflows"
  link "$REPO_ROOT/claude/CLAUDE.md"     "$CLAUDE_HOME/CLAUDE.md"
  link "$REPO_ROOT/claude/RTK.md"        "$CLAUDE_HOME/RTK.md"
  link "$REPO_ROOT/claude/statusline.sh"     "$CLAUDE_HOME/statusline.sh"
  link "$REPO_ROOT/claude/hud-statusline.sh" "$CLAUDE_HOME/hud-statusline.sh"
  link "$REPO_ROOT/claude/settings.json"     "$CLAUDE_HOME/settings.json"

  # skills/ stays a real dir holding links — three populations feed it.
  link "$REPO_ROOT/claude/skills/workflow.md" "$CLAUDE_HOME/skills/workflow.md"
  link "$REPO_ROOT/claude/skills/workflow.ts" "$CLAUDE_HOME/skills/workflow.ts"
  link_skills "$CLAUDE_HOME/skills"
  prune_dead_links "$CLAUDE_HOME/skills"

  install_plugins
  echo
  install_mcp_servers

  if [ "$PROFILE" = "glm" ] || [ "$PROFILE" = "all" ]; then
    step "Claude GLM profile -> $GLM_HOME"
    run mkdir -p "$GLM_HOME"
    render_template "$REPO_ROOT/claude/profiles/glm/settings.json.tmpl" "$GLM_HOME/settings.json" \
      || warn "GLM settings not rendered; \`glm\` will fall back to whatever is already there"
    # Same claude-hud launcher as native; it falls back to ~/.claude's plugin
    # cache until the GLM home has fetched its own copy.
    link "$REPO_ROOT/claude/hud-statusline.sh" "$GLM_HOME/hud-statusline.sh"
    link "$REPO_ROOT/claude/CLAUDE.md"         "$GLM_HOME/CLAUDE.md"
    link "$REPO_ROOT/claude/RTK.md"            "$GLM_HOME/RTK.md"
    # GLM shares one copy of agents and skills with native.
    link "$CLAUDE_HOME/agents" "$GLM_HOME/agents"
    link "$CLAUDE_HOME/skills" "$GLM_HOME/skills"
    info "shell alias: alias glm='CLAUDE_CONFIG_DIR=\"\$HOME/.claude-glm\" claude'"
  fi
}

install_codex() {
  step "Codex -> $CODEX_HOME"
  run mkdir -p "$CODEX_HOME"

  link "$REPO_ROOT/codex/AGENTS.md" "$CODEX_HOME/AGENTS.md"

  # Codex's own skills live in skills/.system/; the glob in link_skills and
  # prune_dead_links skips dotfiles, so that tree is never touched.
  link_skills "$CODEX_HOME/skills"
  prune_dead_links "$CODEX_HOME/skills"

  # Merged, never linked: Codex rewrites this file itself.
  local args=("$REPO_ROOT/codex/config.toml.tmpl" "$CODEX_HOME/config.toml")
  [ "$DRY_RUN" = "1" ] && args+=(--dry-run)
  [ -f "$CODEX_HOME/config.toml" ] && [ "$DRY_RUN" != "1" ] && backup_path_copy "$CODEX_HOME/config.toml"
  # Unguarded, `set -o pipefail` turned any traceback here into an aborted run,
  # so a malformed config.toml meant pi never got installed.
  if ! python3 "$REPO_ROOT/lib/toml_merge.py" "${args[@]}" | sed 's/^/  /'; then
    warn "codex config merge failed — $CODEX_HOME/config.toml left as it was"
    FAILURES=$((FAILURES + 1))
  fi
}

# Copy aside, not move: the merge needs the original in place. Unchanged since
# the newest archived copy means an idempotent re-run — nothing new to keep.
backup_path_copy() {
  local rel; rel="$(backup_rel "$1")"
  local dest="$BACKUP_DIR/$rel" newest
  # `|| true`: with pipefail, find failing on a not-yet-created root would abort.
  newest="$(find "$BACKUP_ROOT" -mindepth 2 -path "*/$rel" -type f 2>/dev/null | sort | tail -1 || true)"
  if [ -n "$newest" ] && cmp -s "$1" "$newest"; then
    skip "$1 (unchanged since $newest)"
    return 0
  fi
  # Its own statement: `mkdir -p -m` only modes the deepest component.
  mkdir -p -m 700 "$BACKUP_DIR"
  mkdir -p "$(dirname "$dest")"
  cp "$1" "$dest"
  info "backed up $1 -> $dest"
}

install_pi() {
  step "pi -> $PI_HOME"
  run mkdir -p "$PI_HOME"

  link "$REPO_ROOT/pi/settings.json" "$PI_HOME/settings.json"

  # Holds the z.ai key: rendered to disk at 600, never a repo file.
  render_template "$REPO_ROOT/pi/models.json.tmpl" "$PI_HOME/models.json" \
    || warn "pi models.json not rendered; set ZAI_API_KEY in $SECRETS_FILE and re-run"

  link_skills "$PI_HOME/skills"
  prune_dead_links "$PI_HOME/skills"
}

[ "$DO_CLAUDE" = 1 ] && { install_claude; echo; }
[ "$DO_CODEX"  = 1 ] && { install_codex;  echo; }
[ "$DO_PI"     = 1 ] && { install_pi;     echo; }

[ "$DRY_RUN" = "1" ] || prune_backups

if [ "$DRY_RUN" = "1" ]; then
  printf '%s\n' "${C_YEL}dry run complete — re-run without --dry-run to apply${C_OFF}"
else
  if [ "$FAILURES" -gt 0 ]; then
    printf '%s\n' "${C_RED}$FAILURES failure(s)${C_OFF} — see the warn lines above"
  else
    printf '%s\n' "${C_GRN}done${C_OFF}"
  fi
  if [ -d "$BACKUP_DIR" ]; then printf '%s\n' "      backups: $BACKUP_DIR"; fi
  printf '%s\n' "      verify with: ./doctor.sh"
  if [ "$FAILURES" -gt 0 ]; then exit 1; fi
fi
