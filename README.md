# agentfiles

Claude Code and Codex setup for macOS, Linux, and WSL.

```sh
git clone https://github.com/xs1128/agentfiles ~/.agentfiles
sh ~/.agentfiles/install.sh
```

Needs `curl`, `git`, `jq` and `unzip`. Rerun to update; a rerun with nothing new
changes nothing. Anything it replaces goes to `~/.agentfiles-backup/`.

## Everything is off

All skills and MCP servers are installed but off, so they cost no context and
no start-up time. Built-in ones are untouched.

| | Claude Code | Codex |
| --- | --- | --- |
| Run a skill | `/name` | `$name` |
| Keep a skill on | `"skillOverrides": {"name": "on"}` in `~/.claude/settings.json` | `allow_implicit_invocation: true` in `skills/name/agents/openai.yaml` |
| Use an MCP server | `claude --mcp-config ~/.claude/mcp/figma.json` | `codex -c mcp_servers.figma.enabled=true` |

## Layout

| Repo | Goes to |
| --- | --- |
| `claude/` | `~/.claude` as links. `settings.json` is merged: repo keys win, machine keys stay. |
| `codex/AGENTS.md` | `~/.codex/AGENTS.md` |
| `skills/` | `~/.claude/skills` and `~/.agents/skills` |
| `mcp/` | `~/.claude/mcp`, and disabled entries in `~/.codex/config.toml` |
| `bin/glm` | `~/.local/bin/glm`: Claude Code on z.ai, key in `~/.agent.env` as `ZAI_API_KEY=...` |

Credits: [CREDITS.md](CREDITS.md).
