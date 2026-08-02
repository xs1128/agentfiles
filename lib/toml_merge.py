#!/usr/bin/env python3
"""Merge a managed TOML fragment into an existing file, in place.

    toml_merge.py <managed.toml> <target.toml> [--dry-run]

Codex rewrites ~/.codex/config.toml itself, so the repo owns only a subset of
keys; everything unmanaged is left exactly as Codex left it. Reads with stdlib
tomllib; writes with a small serializer covering the subset these configs use.
"""

from __future__ import annotations

import sys
import tomllib
from pathlib import Path

BARE_OK = set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")


def deep_merge(base: dict, over: dict) -> dict:
    """Nested dicts merge; scalars and lists replace."""
    out = dict(base)
    for key, val in over.items():
        if isinstance(val, dict) and isinstance(out.get(key), dict):
            out[key] = deep_merge(out[key], val)
        else:
            out[key] = val
    return out


def fmt_key(key: str) -> str:
    return key if key and all(c in BARE_OK for c in key) else '"%s"' % key.replace('"', '\\"')


def fmt_val(val) -> str:
    if isinstance(val, bool):
        return "true" if val else "false"
    if isinstance(val, (int, float)):
        return repr(val)
    if isinstance(val, str):
        return '"%s"' % val.replace("\\", "\\\\").replace('"', '\\"')
    if isinstance(val, list):
        return "[" + ", ".join(fmt_val(v) for v in val) + "]"
    raise TypeError("unsupported TOML value: %r" % (val,))


def dump(data: dict, prefix: tuple[str, ...] = ()) -> list[str]:
    """Scalars at this level first, then recurse into sub-tables."""
    lines: list[str] = []
    scalars = {k: v for k, v in data.items() if not isinstance(v, dict)}
    tables = {k: v for k, v in data.items() if isinstance(v, dict)}

    if scalars and prefix:
        lines.append("[%s]" % ".".join(fmt_key(p) for p in prefix))
    for key, val in scalars.items():
        lines.append("%s = %s" % (fmt_key(key), fmt_val(val)))
    if scalars:
        lines.append("")

    for key, val in tables.items():
        # Tables holding only sub-tables need no header; children use full paths.
        if not val:
            lines.append("[%s]" % ".".join(fmt_key(p) for p in prefix + (key,)))
            lines.append("")
        lines.extend(dump(val, prefix + (key,)))
    return lines


def main() -> int:
    args = [a for a in sys.argv[1:] if a != "--dry-run"]
    dry_run = "--dry-run" in sys.argv[1:]
    if len(args) != 2:
        print(__doc__, file=sys.stderr)
        return 2

    managed_path, target_path = Path(args[0]), Path(args[1])
    managed = tomllib.loads(managed_path.read_text())
    existing = tomllib.loads(target_path.read_text()) if target_path.exists() else {}

    merged = deep_merge(existing, managed)
    if merged == existing:
        print("codex config already matches managed keys")
        return 0

    body = "\n".join(dump(merged)).rstrip() + "\n"
    changed = sorted(k for k in managed if existing.get(k) != managed.get(k))
    if dry_run:
        print("would merge into %s (top-level keys: %s)" % (target_path, ", ".join(changed)))
        return 0

    target_path.parent.mkdir(parents=True, exist_ok=True)
    target_path.write_text(body)
    print("merged managed keys into %s (%s)" % (target_path, ", ".join(changed)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
