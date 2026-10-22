#!/usr/bin/env python3
"""Inventory and verify local folder moves; never mutate the audited tree."""

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import stat
import sys
import unicodedata


def same_or_inside(path, parent):
    return path == parent or parent in path.parents


def relative_path(value):
    if not isinstance(value, str) or not value or "\x00" in value:
        raise ValueError("Mapping paths must be nonempty strings")
    path = PurePosixPath(value)
    if path.is_absolute() or any(p in ("", ".", "..") for p in value.split("/")):
        raise ValueError(f"Unsafe relative path: {value!r}")
    if os.name == "nt" and ("\\" in value or ":" in value):
        raise ValueError(f"Unsafe Windows path: {value!r}")
    return value


def signature(info):
    return info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns, info.st_mode


def scan(root):
    entries = {}

    def visit(directory):
        with os.scandir(directory) as listing:
            children = sorted(listing, key=lambda item: item.name)
        for child in children:
            path = Path(child.path)
            name = path.relative_to(root).as_posix()
            before = path.lstat()
            record = {
                "device": before.st_dev,
                "inode": before.st_ino,
                "mode": stat.S_IMODE(before.st_mode),
                "mtime_ns": before.st_mtime_ns,
            }
            if stat.S_ISLNK(before.st_mode):
                record.update(kind="symlink", target=os.readlink(path))
            elif stat.S_ISDIR(before.st_mode):
                record["kind"] = "directory"
            elif stat.S_ISREG(before.st_mode):
                digest = hashlib.sha256()
                flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
                with os.fdopen(os.open(path, flags), "rb") as handle:
                    if signature(os.fstat(handle.fileno())) != signature(before):
                        raise ValueError(f"Entry changed before hashing: {name!r}")
                    for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                        digest.update(chunk)
                    if signature(os.fstat(handle.fileno())) != signature(before):
                        raise ValueError(f"Entry changed while hashing: {name!r}")
                record.update(kind="file", size=before.st_size, sha256=digest.hexdigest())
            else:
                raise ValueError(f"Unsupported special entry; inventory incomplete: {name!r}")
            if signature(path.lstat()) != signature(before):
                raise ValueError(f"Entry changed during inventory: {name!r}")
            entries[name] = record
            if record["kind"] == "directory":
                visit(path)

    visit(root)
    return entries


def totals(entries):
    return {
        "files": sum(e["kind"] == "file" for e in entries.values()),
        "bytes": sum(e.get("size", 0) for e in entries.values()),
        "symlinks": sum(e["kind"] == "symlink" for e in entries.values()),
        "directories": sum(e["kind"] == "directory" for e in entries.values()),
    }


def write_report(output, data, root):
    destination = Path(output).expanduser().resolve()
    if same_or_inside(destination, root):
        raise ValueError("Audit output must be outside the audited folder")
    destination.parent.mkdir(parents=True, exist_ok=True)
    with destination.open("x", encoding="utf-8") as handle:
        json.dump(data, handle, ensure_ascii=True, indent=2)
        handle.write("\n")


def read_json(path):
    def reject_duplicates(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError(f"Duplicate JSON key: {key!r}")
            result[key] = value
        return result

    with Path(path).open(encoding="utf-8") as handle:
        return json.load(handle, object_pairs_hook=reject_duplicates)


def expected_paths(entries, mapping, portable_names=False):
    if not isinstance(mapping, dict):
        raise ValueError("Mapping must be a JSON object of original paths to final paths")
    unknown = set(mapping) - set(entries)
    if unknown:
        raise ValueError(f"Mapping contains unknown originals: {sorted(unknown)!r}")
    expected = {}
    conservative_names = {}
    for original, record in entries.items():
        relative_path(original)
        destination = relative_path(mapping.get(original, original))
        key = unicodedata.normalize("NFC", destination).casefold() if portable_names else destination
        if key in conservative_names:
            raise ValueError(f"Ambiguous destinations: {destination!r} and {conservative_names[key]!r}")
        conservative_names[key] = destination
        expected[destination] = (original, record)
    for destination in expected:
        for parent in PurePosixPath(destination).parents:
            if str(parent) == ".":
                continue
            key = unicodedata.normalize("NFC", str(parent)).casefold() if portable_names else str(parent)
            ancestor = conservative_names.get(key)
            if ancestor and expected[ancestor][1]["kind"] != "directory":
                raise ValueError(f"Destination traverses a non-directory: {destination!r}")
    return expected


def verify(baseline, mapping, require_identity, portable_names=False):
    if baseline.get("schema") != 1:
        raise ValueError("Unsupported snapshot schema")
    root = Path(baseline["root"]).resolve(strict=True)
    expected = expected_paths(baseline["entries"], mapping, portable_names)
    current = scan(root)
    issues = []
    for destination, (original, before) in expected.items():
        after = current.get(destination)
        if after is None:
            issues.append({"original": original, "destination": destination, "problem": "missing"})
            continue
        fields = ["kind", "mode"]
        if before["kind"] == "file":
            fields += ["size", "sha256", "mtime_ns"]
        elif before["kind"] == "symlink":
            fields += ["target"]
        if require_identity:
            fields += ["device", "inode"]
        changed = [field for field in fields if before.get(field) != after.get(field)]
        if changed:
            issues.append({"original": original, "destination": destination, "problem": "changed", "fields": changed})
    unexpected = sorted(path for path, entry in current.items() if path not in expected and entry["kind"] != "directory")
    issues.extend({"destination": path, "problem": "unexpected"} for path in unexpected)
    return root, {
        "schema": 1,
        "root": str(root),
        "ok": not issues,
        "identity_required": require_identity,
        "before": totals(baseline["entries"]),
        "after": totals(current),
        "issues": issues,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    snapshot = subparsers.add_parser("snapshot", help="Hash all entries without following symlinks")
    snapshot.add_argument("root")
    snapshot.add_argument("--output", required=True)
    check = subparsers.add_parser("verify", help="Verify every original at its mapped destination")
    check.add_argument("baseline")
    check.add_argument("--mapping", required=True)
    check.add_argument("--require-identity", action="store_true")
    check.add_argument("--portable-names", action="store_true", help="Also reject case/Unicode-equivalent destinations")
    check.add_argument("--output", required=True)
    args = parser.parse_args()
    if args.command == "snapshot":
        root = Path(args.root).expanduser().resolve(strict=True)
        if not root.is_dir():
            raise ValueError("Snapshot root must be a directory")
        if same_or_inside(Path(args.output).expanduser().resolve(), root):
            raise ValueError("Audit output must be outside the audited folder")
        entries = scan(root)
        report = {"schema": 1, "root": str(root), "entries": entries, "totals": totals(entries)}
    else:
        root, report = verify(read_json(args.baseline), read_json(args.mapping), args.require_identity, args.portable_names)
    write_report(args.output, report, root)
    summary = report.get("totals") or {"before": report.get("before"), "after": report.get("after"), "issues": len(report.get("issues", []))}
    print(json.dumps({"output": str(Path(args.output).resolve()), "totals": summary, "ok": report.get("ok", True)}))
    return 0 if report.get("ok", True) else 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, KeyError, TypeError) as exc:
        print(f"Audit failed: {exc}", file=sys.stderr)
        sys.exit(2)
