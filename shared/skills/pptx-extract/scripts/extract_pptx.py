#!/usr/bin/env python3
"""Extract text + images from a .pptx PowerPoint deck.

Standard library only (Python 3.14 compatible): a .pptx is a zip archive.
No python-pptx dependency, no pip installs.
"""

import argparse
import os
import re
import shutil
import sys
import tempfile
import zipfile
import xml.etree.ElementTree as ET

# DrawingML namespace holds the text runs (<a:t>).
A_NS = "http://schemas.openxmlformats.org/drawingml/2006/main"
# Relationships namespace for the *.rels files.
REL_NS = "http://schemas.openxmlformats.org/package/2006/relationships"

A_T = f"{{{A_NS}}}t"
A_P = f"{{{A_NS}}}p"
REL_TAG = f"{{{REL_NS}}}Relationship"


def die(msg):
    """Print an error to stderr and exit non-zero."""
    print(f"error: {msg}", file=sys.stderr)
    sys.exit(1)


def slide_number(name):
    """Extract the numeric N from a name like 'slide12.xml' (for numeric sort)."""
    m = re.search(r"(\d+)", os.path.basename(name))
    return int(m.group(1)) if m else 0


def paragraph_text(elem):
    """Join all <a:t> runs inside an element in reading order."""
    return "".join(t.text or "" for t in elem.iter(A_T))


def extract_slide_text(zf, slide_path):
    """Return the slide's text: paragraphs separated by newlines."""
    try:
        data = zf.read(slide_path)
        root = ET.fromstring(data)
    except (KeyError, ET.ParseError):
        return ""
    paras = []
    for p in root.iter(A_P):
        text = paragraph_text(p)
        if text:
            paras.append(text)
    return "\n".join(paras)


def rels_path_for(slide_path):
    """Given ppt/slides/slideN.xml -> ppt/slides/_rels/slideN.xml.rels."""
    d, base = os.path.split(slide_path)
    return f"{d}/_rels/{base}.rels"


def resolve_target(target, base_dir):
    """Resolve a relationship Target (often ../media/x.png) to an archive path."""
    # Archive paths always use forward slashes.
    joined = os.path.normpath(os.path.join(base_dir, target)).replace(os.sep, "/")
    return joined


def slide_media(zf, slide_path, names):
    """Return archive paths of media referenced by this slide, in order."""
    rels = rels_path_for(slide_path)
    if rels not in names:
        return []
    try:
        root = ET.fromstring(zf.read(rels))
    except (KeyError, ET.ParseError):
        return []
    base_dir = os.path.dirname(slide_path)  # ppt/slides
    media = []
    for rel in root.iter(REL_TAG):
        target = rel.get("Target", "")
        if "media/" not in target:
            continue
        resolved = resolve_target(target, base_dir)
        if resolved in names and resolved not in media:
            media.append(resolved)
    return media


def notes_for(zf, slide_path, names):
    """Return speaker-notes text for a slide, or '' if none. Never crashes."""
    rels = rels_path_for(slide_path)
    if rels not in names:
        return ""
    try:
        root = ET.fromstring(zf.read(rels))
    except (KeyError, ET.ParseError):
        return ""
    base_dir = os.path.dirname(slide_path)
    for rel in root.iter(REL_TAG):
        target = rel.get("Target", "")
        if "notesSlide" not in target:
            continue
        resolved = resolve_target(target, base_dir)
        if resolved in names:
            return extract_slide_text(zf, resolved)
    return ""


def main():
    parser = argparse.ArgumentParser(
        description="Extract text + images from a .pptx PowerPoint deck (stdlib only)."
    )
    parser.add_argument("pptx", help="path to the .pptx file")
    parser.add_argument("--out", help="output directory (default: fresh temp dir)")
    args = parser.parse_args()

    pptx = args.pptx
    if not os.path.isfile(pptx):
        die(f"file not found: {pptx}")
    if not zipfile.is_zipfile(pptx):
        die(f"not a valid .pptx (zip) file: {pptx}")

    if args.out:
        out_dir = os.path.abspath(os.path.expanduser(args.out))
        os.makedirs(out_dir, exist_ok=True)
    else:
        out_dir = tempfile.mkdtemp(prefix="pptx_")
    media_dir = os.path.join(out_dir, "media")

    with zipfile.ZipFile(pptx) as zf:
        names = set(zf.namelist())
        slides = sorted(
            (n for n in names
             if re.fullmatch(r"ppt/slides/slide\d+\.xml", n)),
            key=slide_number,
        )

        results = []
        for slide_path in slides:
            text = extract_slide_text(zf, slide_path)
            media_archive = slide_media(zf, slide_path, names)
            notes = notes_for(zf, slide_path, names)

            media_paths = []
            for m in media_archive:
                os.makedirs(media_dir, exist_ok=True)
                dest = os.path.join(media_dir, os.path.basename(m))
                # Avoid clobbering distinct sources sharing a basename.
                if os.path.exists(dest):
                    stem, ext = os.path.splitext(os.path.basename(m))
                    i = 1
                    while os.path.exists(dest):
                        dest = os.path.join(media_dir, f"{stem}_{i}{ext}")
                        i += 1
                with zf.open(m) as src, open(dest, "wb") as dst:
                    shutil.copyfileobj(src, dst)
                media_paths.append(os.path.abspath(dest))

            results.append({
                "n": slide_number(slide_path),
                "text": text,
                "media": media_paths,
                "notes": notes,
            })

    # Report.
    print(f"Output dir: {out_dir}")
    print(f"Slides: {len(results)}")
    print()
    for r in results:
        print(f"=== Slide {r['n']} ===")
        print(r["text"] if r["text"].strip() else "(no text)")
        if r["notes"].strip():
            print(f"Notes: {r['notes']}")
        if r["media"]:
            print("Media: " + ", ".join(r["media"]))
        else:
            print("Media: (none)")
        print()

    print("Open/Read the media image paths above to see the visual mockups.")


if __name__ == "__main__":
    main()
