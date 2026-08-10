#!/usr/bin/env python3
"""Merge a managed TOML fragment into an existing file, in place.

    toml_merge.py <managed.toml> <target.toml> [--dry-run]

Codex rewrites ~/.codex/config.toml itself, so the repo owns only a subset of
keys; everything unmanaged is left exactly as Codex left it. Reads with stdlib
tomllib; writes with a small serializer covering the subset these configs use.
"""

from __future__ import annotations

import datetime
import json
import os
import sys
import tempfile
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


def changed_leaves(managed: dict, existing, prefix: str = "") -> list[str]:
    """Managed leaves that differ. Sub-tables the target holds and the managed
    subset does not are Codex's own and are not drift."""
    out: list[str] = []
    for key, val in managed.items():
        path = prefix + key
        cur = existing.get(key) if isinstance(existing, dict) else None
        if isinstance(val, dict):
            # An empty managed table has no leaves, so it is its own drift.
            if not val and not isinstance(cur, dict):
                out.append(path)
            out.extend(changed_leaves(val, cur, path + "."))
        elif cur != val:
            out.append(path)
    return out


def fmt_key(key: str) -> str:
    return key if key and all(c in BARE_OK for c in key) else '"%s"' % key.replace('"', '\\"')


def fmt_val(val) -> str:
    if isinstance(val, bool):
        return "true" if val else "false"
    if isinstance(val, (int, float)):
        return repr(val)
    if isinstance(val, str):
        # JSON string escaping is a subset of TOML's. ensure_ascii=False is
        # required: the default emits surrogate pairs for astral characters
        # (emoji), which tomllib rejects.
        return json.dumps(val, ensure_ascii=False)
    if isinstance(val, (datetime.datetime, datetime.date, datetime.time)):
        return val.isoformat()
    if isinstance(val, list):
        return "[" + ", ".join(fmt_val(v) for v in val) + "]"
    raise TypeError("unsupported TOML value: %r" % (val,))


def is_table_array(val) -> bool:
    return isinstance(val, list) and bool(val) and all(isinstance(v, dict) for v in val)


def atomic_write(path: Path, body: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    mode = path.stat().st_mode & 0o777 if path.exists() else 0o600
    with tempfile.NamedTemporaryFile("w", dir=path.parent, delete=False) as f:
        tmp = Path(f.name)
        f.write(body)
    os.chmod(tmp, mode)
    os.replace(tmp, path)


def dump(data: dict, prefix: tuple[str, ...] = (), header: bool = True) -> list[str]:
    """Scalars at this level first, then sub-tables, then arrays of tables."""
    lines: list[str] = []
    scalars, tables, arrays = {}, {}, {}
    for key, val in data.items():
        if isinstance(val, dict):
            tables[key] = val
        elif is_table_array(val):
            arrays[key] = val
        else:
            scalars[key] = val

    # header=False: the caller already emitted an [[array]] line for this table.
    if scalars and prefix and header:
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

    for key, val in arrays.items():
        path = ".".join(fmt_key(p) for p in prefix + (key,))
        for item in val:
            lines.append("[[%s]]" % path)
            lines.extend(dump(item, prefix + (key,), header=False))
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
    changed = sorted(changed_leaves(managed, existing))
    if dry_run:
        print("would merge into %s (keys: %s)" % (target_path, ", ".join(changed)))
        return 0

    # Read the serialized form back before committing to it. Turns any future
    # gap in the serializer above into a refusal instead of a corrupted config.
    try:
        reread = tomllib.loads(body)
    except tomllib.TOMLDecodeError as exc:
        print("refusing to write %s: serializer emitted invalid TOML (%s)" % (target_path, exc),
              file=sys.stderr)
        return 1
    if reread != merged:
        lost = sorted(k for k in set(reread) | set(merged) if reread.get(k) != merged.get(k))
        print("refusing to write %s: serializer lost data at %s" % (target_path, ", ".join(lost)),
              file=sys.stderr)
        return 1

    atomic_write(target_path, body)
    print("merged managed keys into %s (%s)" % (target_path, ", ".join(changed)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
