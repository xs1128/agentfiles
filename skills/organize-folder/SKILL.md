---
name: organize-folder
description: Inspect and reorganize a local folder by understanding its contents, proposing a structure, and verifying every original file survives the moves. Use for folder cleanup, tidying, or reorganization, e.g. "organize my Downloads", "clean up this folder", "sort these files".
---

# Organize Folder

Understand the folder before deciding where anything belongs. Preservation is the default: never delete, deduplicate, rename beyond the agreed plan, rewrite contents, or overwrite, unless the user separately authorizes it. Keep duplicates and temp files (an archive folder is usually enough).

## Understand

- Establish the root and scope: plan only, or plan and execute. If the user asks to review first, stop at the plan. Otherwise a request to organize permits routine, reversible moves within scope.
- Inventory the whole tree, including hidden files, empty dirs, archives, and symlinks. Do not follow directory symlinks out of the tree. Report unreadable entries before claiming completeness.
- Classify from representative content, then inspect ambiguous items individually. Read only enough sensitive content to classify it, and do not repeat it in reports.
- Similar names or newer mtimes do not prove duplication or a final version. Distinguish sources, exports, evidence, references, and historical versions.
- Find dependencies before changing paths: repos, linked assets, relative symlinks, app bundles, workbook references, project config. Keep dependent units together. Leave uncertain items in place and flag them.

## Propose

Use a shallow hierarchy by purpose, project, or workflow. Keep source/export pairs together. Mark historical material with meaningful dates or cycles. Preserve original names unless a rename clearly helps and is in scope.

Present: folder purpose, proposed tree, representative mappings, uncertain cases. The internal move mapping must cover every original entry, even if the user-facing plan groups them.

If the user asks for online best practices, read [references/best-practices.md](references/best-practices.md).

## Move

Before any move, snapshot the tree and write the full mapping outside the target folder. `${CLAUDE_SKILL_DIR}` is this skill's directory (in Codex, the folder holding this file).

```bash
python3 ${CLAUDE_SKILL_DIR}/scripts/inventory.py snapshot <root> --output /tmp/<name>-audit/before.json
```

`moves.json` maps original relative paths to final relative paths, e.g. `{"notes.docx": "Project/notes.docx", "old": "Reference", "old/guide.pdf": "Reference/guide.pdf"}`. A directory mapping does not cover its descendants: list each one. Unlisted paths are expected unchanged.

- Check each destination for collisions (case and Unicode equivalents too) on the real filesystem. Resolve them in the plan.
- Prefer whole-directory moves when they keep groupings and dependencies intact. Create only the directories the plan needs.
- Use a no-overwrite move (`mv -n`). It can skip silently, so confirm source gone and destination present after each move. Log completed moves to an external journal.
- Use same-filesystem renames only. If a move would cross filesystems, explain and stop that move.
- On any failure, changed source, or mismatch: stop dependent moves, report actual state, re-inspect, and propose recovery from the journal. No blind retries or automatic rollback.

## Verify and report

```bash
python3 ${CLAUDE_SKILL_DIR}/scripts/inventory.py verify /tmp/<name>-audit/before.json --mapping /tmp/<name>-audit/moves.json --require-identity --output /tmp/<name>-audit/verification.json
```

It checks size, SHA-256, mode, symlink targets, and inode identity for every original, and flags unexpected files. Exit 0 means pass. Add `--portable-names` to reject case/Unicode-equivalent destinations. It does not check extended attributes.

Report the final tree, files preserved, verification result, unresolved items, and audit location. Never claim success while anything is missing, changed, or unaccounted for. Files created by other apps during the work are kept and listed separately.
