# agentfiles

My Claude Code and Codex setup — memory, subagents, skills, plugins — as a repo
you clone and link. Mac and Linux, one script, no sudo.

## Install

```sh
git clone git@github.com:xs1128/agentfiles.git ~/.agentfiles
sh ~/.agentfiles/install.sh
exec $SHELL
```

Installs Claude Code, Codex, bun and rtk if missing, symlinks `claude/` into
`~/.claude` and `codex/` into `~/.codex`, and installs the pinned plugins.
Needs `curl`, `git`, `jq`.

Rerun it to update. Safe to rerun.

| flag | effect |
| --- | --- |
| `--no-deps` | skip the installs |
| `--no-bootstrap` | skip the plugins |
| `--no-codex` | Claude Code only |
| `--mcp` | also install the MCP servers (needs node) |

Because both directories are symlinks into the clone, editing a skill here takes
effect next session, in either harness.

## Codex

Three things, nothing else: rtk, the skills, the bundled plugins.

    codex/AGENTS.md   → ~/.codex/AGENTS.md   the rtk rule
    skills/*          → ~/.codex/skills/*    the same 45 directories Claude gets
    plugins.toml.tmpl → appended to ~/.codex/config.toml

Codex has no PreToolUse hook, so rtk is an instruction in `AGENTS.md` rather
than a rewrite. It costs a few tokens per session that the Claude side gets for
free.

`config.toml` is Codex's own — it writes to it during sessions — so the plugin
enables are appended instead of symlinked, and only for a block the file does
not already have. Nothing there is ever rewritten, so a plugin you turned off by
hand stays off, and the previous copy lands in `~/.codex/backups/`. Model and
reasoning effort are deliberately not pinned: they are set in Codex's UI, and
writing them here would revert that on every install.

Re-link without touching the rest:

```sh
sh scripts/link-codex.sh
```

## GLM

Put the key in `~/.agent.env`, readable only by you:

```sh
install -m 600 /dev/null ~/.agent.env
echo 'ZAI_API_KEY=your-key-here' >> ~/.agent.env
```

Then:

```sh
glm
```

Same config against z.ai: opus → `glm-5.2`, sonnet → `glm-5-turbo`, haiku →
`glm-4.7`. Plain `claude` is unaffected. `ZAI_API_KEY` in the environment wins
over the file.

## MCP

Not installed by default, and never loaded implicitly — a server costs tool
definitions in every prompt.

```sh
sh scripts/bootstrap.sh --mcp
```

Then load per session:

```sh
claude --mcp-config ~/.claude/mcp/web.json --strict-mcp-config    # playwright
claude --mcp-config ~/.claude/mcp/cloud.json --strict-mcp-config  # firebase
```

Playwright's tools error until a browser is installed: `npx playwright install
chromium`.

## Skills

Loaded by both harnesses out of `skills/`. Vendored from upstream at pinned
commits. To pull newer ones:

```sh
sh scripts/sync-skills.sh
```

That recopies from the commits `manifests/skills.json` names, so upstream changes
arrive as a reviewable diff.

## Plugins

`caveman` and `claude-hud` only, pinned in `manifests/plugins.json`. Change a pin
and rerun `sh scripts/bootstrap.sh`.

## Layout

    claude/       symlinked into ~/.claude
    codex/        symlinked into ~/.codex
    skills/       loaded by both
    manifests/    pinned plugins, MCP packages, skill sources
    scripts/      link, link-codex, bootstrap, glm, sync-skills
    install.sh

## Uninstall

Everything this repo puts on the machine is a symlink into the clone, so
unlinking is most of the job:

```sh
find ~/.claude ~/.codex -maxdepth 2 -type l \
  -exec sh -c 'readlink "$1" | grep -q "/.agentfiles/" && rm "$1"' _ {} \;
rm -f ~/.local/bin/glm ~/.codex/skills/.agentfiles-managed
```

Then drop the `# agentfiles` block from your shell rc. Whatever was replaced is
under `~/.claude/backups/` and `~/.codex/backups/`. The plugin blocks appended to
`~/.codex/config.toml` are left behind; delete them by hand.

The tools are a separate question, and both of these throw away auth and history:

```sh
rm -rf ~/.local/bin/claude ~/.local/share/claude ~/.claude ~/.claude.json
rm -rf ~/.codex ~/.local/bin/codex ~/.local/bin/codex-code-mode-host
```

Codex keeps its binary under `~/.codex`, so that one line takes the install with
it. `bun` is `rm -rf ~/.bun`. rtk ships no uninstaller — delete whatever `which
rtk` names.

## Attribution

Most skills are other people's work, MIT licensed and vendored. See
[CREDITS.md](CREDITS.md).
