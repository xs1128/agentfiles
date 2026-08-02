# agent-config

Reproducible configuration for the coding agents I use: **Claude Code**, **Codex**, and **pi**.

One repo, one branch, one directory per agent. `./install.sh` links it into each
agent's home and fetches every skill and plugin at a pinned version, so a fresh
machine ends up matching this one.

## Setup

Every command below is idempotent — re-run any of them any time.

**0. Get the repo** (once per machine)

```bash
git clone <this-repo> ~/Desktop/code/agent-config
cd ~/Desktop/code/agent-config
./install.sh --all --dry-run       # prints every action, changes nothing
```

Read that output. Everything after this point is the same command without
`--dry-run`.

**1. Pick your agents**

Interactively:

```bash
./setup                            # bubbletea wizard: agents, profile, dry-run/install/doctor
```

Or directly — the wizard just builds one of these and runs it:

```bash
./install.sh --claude              # one
./install.sh --claude --pi         # some
./install.sh --all                 # claude + codex + pi
```

The first run creates `~/.config/agent-secrets.env` and warns that `ZAI_API_KEY`
is empty. That is expected — nothing else is blocked by it.

**2. Add the key** (only needed for pi, or the Claude GLM profile)

```bash
$EDITOR ~/.config/agent-secrets.env    # ZAI_API_KEY=...
./install.sh --all                     # re-run; renders pi/models.json at 600
```

**3. Add the GLM profile** (optional, Claude only)

```bash
./install.sh --claude --profile glm
echo "alias glm='CLAUDE_CONFIG_DIR=\"\$HOME/.claude-glm\" claude'" >> ~/.zshrc
```

`claude` stays native Anthropic; `glm` is the same setup pointed at z.ai. Both
share one copy of the subagents and skills.

**4. Verify**

```bash
./doctor.sh                        # all agents; non-zero exit if drifted
./doctor.sh --claude               # just one
```

### Day to day

| Situation | Command |
|---|---|
| Changed a config in the repo | Nothing — configs are symlinks, already live |
| Changed `claude/plugins.json` or a manifest | `./install.sh --all` |
| Something feels wrong | `./doctor.sh` |
| Don't want to remember flags | `./setup` |
| New machine | Steps 0–4 |
| Undo | Replaced configs are in `~/.agent-config-backups/<timestamp>/` — newest 10 runs, byte-identical files not copied |

Restarting the agent picks up config changes; `settings.json` and `agents/` are
read at launch.

## Layout

```
setup                   build + launch the TUI wizard (a front-end for the two scripts below)
install.sh              link configs, install skills/plugins, render secrets
doctor.sh               read-only health check; non-zero exit if drifted
lib/                    installer internals (common, deps, skills, plugins, secrets, toml_merge)
tui/                    bubbletea wizard (Go). Owns no install logic — shells out to the scripts

shared/
  skills/               skills I wrote that any agent can use
  manifests/
    skills.json         42 third-party skills, pinned to a commit per source
    wiki.json           my xs-llm-wiki skills, cloned as a live checkout
    deps.json           host tools each agent hard-depends on

claude/
  settings.json         model, rtk hook, statusline, enabled plugins
  CLAUDE.md, RTK.md     global instructions (CLAUDE.md is just `@RTK.md`)
  agents/               9 subagents
  workflows/            agent-pipelines.yaml + README
  skills/               workflow.md / workflow.ts (the /workflow runner)
  plugins.json          marketplaces + plugins, pinned by version and commit
  hud-statusline.sh     launcher for the claude-hud plugin's bun entrypoint
  statusline.sh         pure-bash statusline; fallback, not wired by default
  profiles/glm/         settings.json.tmpl for the z.ai variant
codex/
  config.toml.tmpl      managed keys only: MCP servers, plugins, desktop, approvals_reviewer
                        (not model/reasoning effort — those are Codex's own UI choice)
  AGENTS.md             global instructions; the rtk rules, inlined (see below)
pi/                     settings.json, models.json.tmpl
```

## The three mandatory pieces

| Piece | What it is | Installed by | Enforced by |
|---|---|---|---|
| **rtk** | Call proxy for token savings. Claude wires it as a `PreToolUse` hook; Codex has no such hook, so it gets the rules as instructions instead | host binary (`brew install rtk`) | `deps.json` — install.sh refuses to continue without it |
| **caveman** | Response-compression mode | plugin `caveman@caveman` | `plugins.json` `"required": true` |
| **claude-hud** | Statusline | plugin `claude-hud@claude-hud` | `plugins.json` `"required": true` |

`install.sh` verifies the two required plugins actually landed rather than
trusting the `claude plugin install` exit code, and `doctor.sh` fails if any of
the three is absent. Nothing here is reimplemented — `hud-statusline.sh` only
locates the newest installed claude-hud version and hands stdin to its own
`src/index.ts`. It exists because the equivalent used to be a single inlined
`bash -c` string in `settings.json` with an absolute `bun` path baked in, which
made the config unportable.

## Why directories, not branches

The three agents run on the same machine at the same time, and they share
assets — the 42 third-party skills are symlinked into both `~/.claude/skills`
and `~/.pi/agent/skills` from a single copy on disk. A branch can only be
checked out once, so `--all` would be impossible without extra worktrees, and
every shared change would need cherry-picking across three heads.

Variants of a single agent are **profiles**, not branches, for the same reason:
`~/.claude` and `~/.claude-glm` coexist. See `claude/profiles/`.

## How each config reaches its agent

| Config | Method | Why |
|---|---|---|
| `claude/{agents,workflows,settings.json,…}` | symlink | Edit in the repo, `git diff` shows it immediately |
| `codex/config.toml` | **merge** | Codex rewrites this file itself (project trust, marketplace caches, TUI state). Only the managed key subset is applied; everything else is left alone |
| `pi/models.json` | **render** | Holds the z.ai API key. Written to disk at `600`, never a repo file |
| skills | symlink from one shared copy | A skill exists once, however many agents see it |

Symlinks carry writes in both directions. `claude/settings.json` *is* the file
Claude Code edits, so picking a model with `/model` writes straight into this
repo's working tree — the committed `"model": "opus[1m]"` arrived that way, not
by hand. Check `git status` before `git add -A`, or an interactive choice rides
along inside an unrelated commit.

MCP servers reach the two agents by different routes for the same reason. Claude
keeps them in `~/.claude.json`, which it rewrites itself, so `claude/mcp.json`
holds the definitions and `install.sh` applies them with `claude mcp add-json`.
Codex keeps them in `config.toml`, so the merge above already covers them and
they live directly in `codex/config.toml.tmpl`.

They do not end up with the same set by the same route. `claude/mcp.json`
defines only **firebase** and **playwright**; Claude gets **figma** from the
`figma@claude-plugins-official` plugin instead. Codex gets all three from
`config.toml`. The npm-published two are pinned to an exact version in both
files — bumping them is a reviewable manifest diff, not a silent `@latest`
refetch on every session.

### Why codex/AGENTS.md inlines the rtk rules

`rtk init -g --codex` writes a `~/.codex/RTK.md` and appends an
`@/absolute/path/RTK.md` line to `AGENTS.md`. Codex 0.145 does not resolve `@`
imports — it inlines `AGENTS.md` verbatim into the prompt, so that line arrives
as literal text and the rules never reach the model:

```
$ codex debug prompt-input
# AGENTS.md instructions
<INSTRUCTIONS>
@/Users/…/.codex/RTK.md          # ← not expanded
</INSTRUCTIONS>
```

So `codex/AGENTS.md` carries the rule text itself, and there is no `codex/RTK.md`.
This is the one place Codex deliberately diverges from `claude/CLAUDE.md`, which
*is* just `@RTK.md`. The cost is that `rtk init --codex --show` reports "not
configured" — its detector looks for the import line. `doctor.sh` checks the
thing that actually matters instead, by grepping `codex debug prompt-input`.

Codex deliberately gets **no caveman mode** — it has no plugin system, so if it
were ever wanted the rules would have to be inlined into `codex/AGENTS.md` as
rule text, exactly like the rtk rules above.

Any **config** already occupying a target path is moved to
`~/.agent-config-backups/<timestamp>/` first — the installer never clobbers one.
Byte-identical files are dropped rather than archived, and only the ten newest
runs are kept.

The one exception is third-party skills: `~/.agents/skills/<name>` is replaced
outright from the pinned source, not backed up. It is a copy of upstream, and
before copying, the installer checks both that the pinned tree matches
`folderHash` and that the source worktree matches that tree — so a locally
modified source is skipped rather than propagated into all three agents.

## Secrets

Nothing credential-shaped is committed. All keys live in one gitignored file:

```
~/.config/agent-secrets.env      # chmod 600, created by install.sh on first run
```

| Variable | Used by |
|---|---|
| `ZAI_API_KEY` | Claude GLM profile (`ANTHROPIC_AUTH_TOKEN`) and pi's `zai` provider |

`doctor.sh` greps the **working tree** (not the index — with nothing staged that
scanned nothing) for API-key-shaped strings, and also checks where a real key
actually lands: the rendered `pi/models.json` and GLM `settings.json`, and
`~/.agent-config-backups/`. It fails naming the offending file. It reads the
secrets file with a small parser rather than sourcing it, so a stray line in a
hand-edited file is never executed.

## Profiles

| Profile | Home | Model |
|---|---|---|
| `native` (default) | `~/.claude` | Anthropic, Opus |
| `glm` | `~/.claude-glm` | z.ai GLM via `ANTHROPIC_BASE_URL` |

```bash
./install.sh --claude --profile glm
alias glm='CLAUDE_CONFIG_DIR="$HOME/.claude-glm" claude'   # in ~/.zshrc
```

The GLM profile symlinks `agents/` and `skills/` back to `~/.claude`, so both
environments share one set of subagents.

## Claude subagents and workflows

`claude/agents/` holds nine subagents — `orchestrator`, `scout`, `planner`,
`plan-reviewer`, `builder`, `reviewer`, `red-team`, `documenter`, `bowser`.
Run a session on the orchestrator and prompt it to *strictly follow your agentic
workflow*; it dispatches the rest sequentially or in parallel.
Subagent design credit: [disler](https://github.com/disler/pi-vs-claude-code/tree/main).

`claude/workflows/agent-pipelines.yaml` chains them into seven named pipelines
(`plan-build-review`, `plan-build`, `scout-flow`, `plan-review-plan`,
`full-review`, `build-review-loop`, `weekly-sweep`), invoked with
`/workflow <name> "<task>"`. Each step's output feeds the next as `$INPUT`.
See `claude/workflows/README.md`.

## Updating pins

Skills and plugins are both pinned by commit SHA, but only the skill pins are
**enforced**. Each skill's tree is hashed against `folderHash`, and its source
worktree checked against that tree, before anything is copied — a mismatch skips
that skill and fails the run.

Plugin pins are **reported only**. `claude plugin install` takes no version or
commit flag and always fetches latest, so all the installer can do is read the
`version`/`gitCommitSha` that actually landed back out of
`installed_plugins.json` and compare. A mismatch is a warning telling you to bump
the pin — reinstalling would just refetch latest, so it cannot fix anything.

The wiki is the exception: it is a live checkout you edit, so it is never reset.
Its `commit` is a drift warning only.

To take upstream changes, bump the `commit` field in the relevant manifest and
re-run the installer — the update is a reviewable diff, never a surprise.

```bash
git ls-remote https://github.com/mattpocock/skills.git HEAD   # get the new SHA
$EDITOR shared/manifests/skills.json
./install.sh --all
```
