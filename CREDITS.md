# Credits

This repository redistributes work by others.

## Skills

41 of the skills under `skills/` come from
[mattpocock/skills](https://github.com/mattpocock/skills): 33 at commit
`84fdeffd12f2ee307994d1eb6feb48173b6e0502`, and 8 more that the repo has since
deleted, taken at the last commit that carried each.

`emil-design-eng` comes from
[emilkowalski/skills](https://github.com/emilkowalski/skills) at commit
`78761e1b57f97dce65b983d640c70a68f39e8163`.

`manifests/skills.json` names which skills came from where.

## Plugins

`bootstrap.sh` installs plugins from marketplaces this repo does not own, each
pinned to a commit in `manifests/plugins.json`. They are cloned at install time
and remain under their own licenses:

- [JuliusBrussee/caveman](https://github.com/JuliusBrussee/caveman)
- [jarrodwatts/claude-hud](https://github.com/jarrodwatts/claude-hud)

The plugins Codex enables in `codex/plugins.toml.tmpl` ship with Codex itself
and are not redistributed here.

## Tools

Claude Code, Codex, `rtk` and `bun` are installed from their upstream installers
by `install.sh` and are not redistributed as source here.

## License

The vendored skills above are MIT licensed. MIT requires the notice to travel
with the copies, so it is reproduced here in full.

MIT License

Copyright (c) 2026 Matt Pocock
Copyright (c) 2026 Emil Kowalski

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
