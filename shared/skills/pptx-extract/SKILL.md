---
name: pptx-extract
description: Extracts all slide text and embedded images from a .pptx PowerPoint deck (stdlib-only, no python-pptx) so you can read a deck's contents and describe its visual mockups. Triggers on: "extract pptx", "read this powerpoint", "read the .pptx", "extract slides", "what's in this deck", "pptx", "/pptx-extract".
allowed-tools: Read Bash
---

# pptx-extract: PowerPoint text + image extractor

## What it does
Pulls every slide's text and every embedded image out of a `.pptx` deck. A `.pptx` is just a zip archive, so the bundled `scripts/extract_pptx.py` unzips it in memory, reads the `<a:t>` text runs from each `ppt/slides/slideN.xml` (in numeric slide order), maps each slide's images via its `_rels` file, copies the referenced media into an output dir, and prints a per-slide report of text plus the absolute paths of the copied images. Speaker notes are included when present.

## Usage
```bash
python3 /Users/xsooi1128/.claude/skills/pptx-extract/scripts/extract_pptx.py "/path/to/deck.pptx"
```
Pass `--out <dir>` to choose the output directory; otherwise a fresh temp dir under the system temp is created and its path is printed at the top of the report.

## After running
The script gives you the text and the image file locations, not the visual analysis. To describe the actual UI/mockups, **Read the printed media image paths** (the `Media: ...` lines) so you can see and describe each slide's images.

## Notes
- Standard library only (`zipfile`, `xml.etree.ElementTree`, `shutil`, `argparse`, `tempfile`, `re`). No `python-pptx`, no pip installs required.
- A `.pptx` is a zip file; slides are enumerated numerically (slide2 before slide10), not lexically.
- Robust to decks with no media, no text, or missing `_rels`; exits non-zero with a clear message only if the file is missing or not a valid zip.

Triggers on: "extract pptx", "read this powerpoint", "read the .pptx", "extract slides", "what's in this deck", "pptx", "/pptx-extract".
