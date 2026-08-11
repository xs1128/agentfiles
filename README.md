# agentfiles

My Claude Code setup — memory, subagents, skills, plugins, MCP — as a container
image, so a box needs a container runtime and nothing else. No package manager,
no writable npm prefix, no sudo.

Mac and Linux run the same image the same way, so the environment is the same
one in both places.

## Use it

```sh
curl -fsSL https://raw.githubusercontent.com/xs1128/agentfiles/main/install.sh | sh
exec $SHELL
cd any/project && agent
```

That drops the launcher in `~/.local/bin` and puts it on `$PATH` in your shell's
rc file. Add `-s -- --alias` to the curl to also alias `claude` to it. Keys go in
`.env` next to you, or `~/.agent.env`.

`agent` finds docker, podman, apptainer, singularity, or enroot, and runs the
image against the current directory as your own uid, so what it writes belongs
to you. Don't run it under `sudo`: the files would come out root's. If docker
needs root on your box, put yourself in the docker group once
(`sudo usermod -aG docker $USER`, then log back in) rather than prefixing every
run.

```sh
./agent                  # no MCP servers
./agent --mcp web        # + playwright
./agent --mcp web,cloud  # + playwright and firebase
```

MCP categories live in `config/mcp/`. None load by default: a server's cost is
the tool definitions it adds to every prompt, not the disk it takes.

## What the container can see

The directory you ran it from, mounted at that same path so what it prints
matches your shell, and a state dir at `/state`. Nothing else in your home
directory. An ssh-agent socket is forwarded if you have one, so it can push;
without one it can still commit.

Credentials come from the env file at runtime and are never in an image layer.

## The state dir

`~/.agent-state` holds what must survive a session: login, history, todos. The
image's config is a template copied in on first run, recopied when the image
version changes. Upgrading the image does not lose your sessions.

## Layout

    config/          copied into the image, and symlinkable into ~/.claude
      CLAUDE.md      global memory
      settings.json
      agents/        subagents
      skills/        45 skills
      workflows/     agent pipelines
      mcp/           MCP categories, opt-in
    manifests/       build inputs: pinned plugins, MCP packages, skill sources
    scripts/         bootstrap (build), entrypoint (run), link, sync-skills
    agent            the launcher
    install.sh       puts the launcher on $PATH

## Running natively instead

The container is the supported path on both platforms. If you also want Claude
Code installed on the host reading the same `config/` — handy for editing skills
and seeing the change without a rebuild:

```sh
sh scripts/link.sh   # symlinks config/ into ~/.claude; moves what was there to ~/.claude/backups
```

That needs `claude`, `rtk` and `bun` installed yourself, and it sees your whole
home directory. The image is what reproduces.

## Building

CI builds and pushes `linux/amd64` and `linux/arm64` to
`ghcr.io/xs1128/agentfiles` on every push to main, and tags `vN.N.N` from git
tags. `docker build .` builds locally if you need it.

Plugins are pinned to commits in `manifests/plugins.json`;
`sh scripts/sync-skills.sh` recopies vendored skills from the commits
`manifests/skills.json` pins.

## Attribution

Most skills here are other people's work, MIT licensed and vendored. See
[CREDITS.md](CREDITS.md).
