# agent-config

Small, reproducible setup for Claude Code, Codex, and pi.

## Run

macOS, Linux, FreeBSD, or WSL/Git Bash:

```bash
./setup
```

Windows PowerShell:

```powershell
.\setup.ps1
```

Setup detects the OS, offers to install Go when it is missing, builds the TUI,
and opens it. `ASSUME_YES=1` answers that prompt; declining still leaves the
scripts below usable.

Choose:

- Agents: Claude, Codex, pi
- Components: dependencies, config, skills, plugins, MCP
- Claude profile: native or GLM
- Action: dry run, install, doctor

Direct CLI remains available:

```bash
./install.sh --all --dry-run
./install.sh --claude --codex --config --skills --mcp
./install.sh --all --install-deps
./doctor.sh --all
```

With no component flags, the CLI manages everything for compatibility. The TUI
uses explicit opt-ins.

## Safety

- Existing config is backed up under `~/.agent-config-backups/`.
- Secrets are parsed as data, never executed.
- Secret files are mode `600`, written atomically, and never backed up.
- Removing a key removes stale rendered credentials.
- Skills are pinned and verified. Only installer-owned stale skills are removed.
- Claude marketplaces are checked out at pinned commits.
- Codex TOML is merged atomically; unmanaged keys stay untouched.

Secrets live in:

```text
~/.config/agent-secrets.env
```

## Files

```text
setup / setup.ps1     OS bootstrap + TUI launcher
install.sh            apply selected components
doctor.sh             read-only verification
lib/                  installer modules
tui/                  small Bubble Tea selector
shared/manifests/     dependencies and pinned skills
claude/ codex/ pi/    agent-specific config
```

The wiki checkout is intentionally live; all other external skills and Claude
marketplaces are pinned.

## Verify

```bash
make test
make lint
```

CI runs on macOS, Linux, and Windows.
