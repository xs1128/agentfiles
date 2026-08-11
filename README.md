# agentfiles

My Claude Code setup — memory, subagents, skills, plugins, MCP — as a repo you
clone and link. Mac and Linux, one script, no sudo.

## Use it

```sh
git clone https://github.com/xs1128/agentfiles
sh agentfiles/install.sh
exec $SHELL
claude
```

`install.sh` installs what is missing (claude-code, bun, rtk), symlinks `config/`
into `~/.claude`, and installs the plugins and MCP servers the manifests pin. It
is safe to rerun. `--no-deps` skips the installs, `--no-bootstrap` skips the
plugins.

Nothing needs root. If node's global prefix belongs to root, the installer moves
your npm prefix to `~/.local` rather than reaching for sudo. `~/.local/bin` and
`~/.bun/bin` are added to `$PATH` in your shell's rc file.

Because `~/.claude` is symlinks into the clone, editing a skill here takes effect
in the next session — no reinstall.

## GLM instead of Anthropic

```sh
claude-glm
```

Same config, pointed at z.ai: opus maps to `glm-5.2`, sonnet to `glm-5-turbo`,
haiku to `glm-4.7`. It needs `ZAI_API_KEY`, from your environment or from
`~/.agent.env` (see `.env.example`). Plain `claude` is unaffected.

## MCP servers

None load by default: a server's cost is the tool definitions it adds to every
prompt, not the disk it occupies. Load a category when you want it:

```sh
claude --mcp-config ~/.claude/mcp/web.json --strict-mcp-config    # playwright
claude --mcp-config ~/.claude/mcp/cloud.json --strict-mcp-config  # firebase
```

## Layout

    config/          symlinked into ~/.claude by install.sh
      CLAUDE.md      global memory
      settings.json
      agents/        subagents
      skills/        45 skills
      workflows/     agent pipelines
      mcp/           MCP categories, opt-in
      plugins/       config for installed plugins
    manifests/       pinned plugins, MCP packages, skill sources
    scripts/         install steps: link, bootstrap, glm, sync-skills
    install.sh       the whole setup

## Updating

Plugins are pinned to commits in `manifests/plugins.json`; rerun
`sh scripts/bootstrap.sh` after changing them. `sh scripts/sync-skills.sh`
recopies vendored skills from the commits `manifests/skills.json` pins, so an
upstream change arrives as a reviewable diff.

## Attribution

Most skills here are other people's work, MIT licensed and vendored. See
[CREDITS.md](CREDITS.md).
