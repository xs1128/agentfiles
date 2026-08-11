#!/usr/bin/env python3
"""Turn a training log into line charts (epoch/step vs metric).

Handles logs written by `rich` (the format used by SGLang / EAGLE-3 / most
HF-style trainers), where one metrics record is soft-wrapped across many
lines with a timestamp column on the left and a `trainer.py:233` source
column on the right. Plain one-line-per-record logs work too.

Examples:
    # see what metrics the log actually contains
    plot_training_log.py train.out --list

    # default: auto-panels (accuracy / loss / lr), Times New Roman
    plot_training_log.py train.out -o chart.png

    # explicit panels, "Title:regex" -- repeat for more panels
    plot_training_log.py train.out \
        --panel "Accuracy:full_acc" --panel "Loss:loss_\\d" --x epoch
"""

import argparse
import re
import sys
from pathlib import Path

import matplotlib
import matplotlib.pyplot as plt
from matplotlib.ticker import MaxNLocator

# --------------------------------------------------------------------------
# log flattening
# --------------------------------------------------------------------------

ANSI = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")
# "[05:39:12 AM] INFO   " / "2024-01-01 05:39:12,123 INFO " / bare continuation
PREFIX = re.compile(
    r"^(?:\[?\d{2,4}[-:]\d{2}[-:]\d{2}[^\]]*\]?|\s{0,16})\s*"
    r"(?:INFO|WARNING|WARN|ERROR|DEBUG)?\s*"
)
# trailing source-location column, e.g. "trainer.py:233"
SUFFIX = re.compile(r"\s+[\w./-]+\.py:\d+\s*$")
# rich progress bars redraw constantly and carry no metrics
PROGRESS = re.compile(r"[━╸╺]|\d+/\d+\s+\[|\d+%\|")

# A metric key: `train/loss_0`, `val/full_acc_1_epoch`, `eval_loss`, `lr`.
KEY = r"[A-Za-z][\w]*(?:/[\w]+)*"
NUM = r"[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?"
KV = re.compile(rf"({KEY})=({NUM})")


def flatten(path: Path) -> str:
    """Strip decoration columns and join the whole log into one line."""
    parts = []
    for raw in path.read_text(errors="replace").splitlines():
        line = ANSI.sub("", raw)
        if PROGRESS.search(line):
            continue
        line = SUFFIX.sub("", PREFIX.sub("", line))
        parts.append(line.strip())
    return " ".join(parts)


def parse(path: Path, x_key: str = "epoch"):
    """Extract metric records from a log.

    Returns a list of {key: float} dicts, each containing the x-axis key.
    A record runs from one occurrence of the x key to the next, so wrapped
    multi-line records reassemble correctly.

    The `(?<!\\w)` guard matters: without it, `epoch=` also matches inside
    key names like `val/full_acc_0_epoch=0.53`, which silently truncates
    every record and yields zero usable data.
    """
    text = flatten(path)
    boundary = re.compile(rf"(?<!\w){re.escape(x_key)}=({NUM})")

    records, cursor = [], 0
    for match in boundary.finditer(text):
        chunk = text[cursor:match.end()]
        cursor = match.end()
        rec = {}
        for kv in KV.finditer(chunk):
            key, value = kv.group(1), kv.group(2)
            try:
                rec[key] = float(value)
            except ValueError:
                pass
        if x_key in rec and len(rec) > 1:
            records.append(rec)
    return records


# --------------------------------------------------------------------------
# series building
# --------------------------------------------------------------------------


def collect(records, key, x_key, agg="mean"):
    """{x: value} for one metric, aggregating repeats within the same x."""
    buckets = {}
    for rec in records:
        if key in rec:
            buckets.setdefault(rec[x_key], []).append(rec[key])
    if agg == "last":
        return {x: v[-1] for x, v in sorted(buckets.items())}
    if agg == "max":
        return {x: max(v) for x, v in sorted(buckets.items())}
    if agg == "min":
        return {x: min(v) for x, v in sorted(buckets.items())}
    return {x: sum(v) / len(v) for x, v in sorted(buckets.items())}


def metric_keys(records, x_key):
    """Every metric key seen, with how many records carry it."""
    counts = {}
    for rec in records:
        for key in rec:
            if key != x_key:
                counts[key] = counts.get(key, 0) + 1
    return dict(sorted(counts.items()))


AUTO_PANELS = [
    ("Accuracy", r"acc"),
    ("Loss", r"loss"),
    ("Learning rate", r"\blr\b|learning_rate"),
]


def auto_panels(keys):
    """Pick panels that actually match something in this log."""
    panels = []
    for title, pattern in AUTO_PANELS:
        rx = re.compile(pattern, re.I)
        if any(rx.search(k) for k in keys):
            panels.append((title, pattern))
    return panels or [("Metrics", r".")]


# --------------------------------------------------------------------------
# styling
# --------------------------------------------------------------------------

PALETTE = ["#1f77b4", "#ff7f0e", "#2ca02c", "#d62728",
           "#9467bd", "#8c564b", "#e377c2", "#7f7f7f"]
# train curves render dashed and faded; val/eval/test render solid
TRAIN = re.compile(r"^train|_train|\btrain/", re.I)


def use_font(preferred="Times New Roman"):
    """Serif rendering; falls back through common Times clones."""
    from matplotlib import font_manager

    available = {f.name for f in font_manager.fontManager.ttflist}
    for name in (preferred, "Times New Roman", "Times",
                 "Nimbus Roman", "Liberation Serif", "DejaVu Serif"):
        if name in available:
            plt.rcParams["font.family"] = "serif"
            plt.rcParams["font.serif"] = [name] + plt.rcParams["font.serif"]
            plt.rcParams["mathtext.fontset"] = "stix"
            return name
    plt.rcParams["font.family"] = "serif"
    print(f"warning: {preferred!r} not found, using default serif", file=sys.stderr)
    return "serif"


MARKERS = ["o", "s", "^", "D", "v", "P"]


def base_name(key):
    """`val/full_acc_1_epoch` -> `full_acc` (strips split, index, suffix)."""
    name = re.sub(r"^(train|val|eval|test)[/_]", "", key, flags=re.I)
    name = re.sub(r"_epoch$", "", name)
    return re.sub(r"_?\d+$", "", name)


def style_for(key, index, families=()):
    """Color by head index, dash by train-vs-eval, marker by metric family."""
    stem = re.sub(r"_epoch$", "", key)
    tail = re.search(r"(\d+)$", stem)
    color = PALETTE[(int(tail.group(1)) if tail else index) % len(PALETTE)]
    is_train = bool(TRAIN.search(key))
    family = base_name(key)
    marker = MARKERS[families.index(family) % len(MARKERS)] if family in families else "o"
    return {
        "color": color,
        "linestyle": "--" if is_train else "-",
        "marker": "" if is_train else marker,
        "alpha": 0.55 if is_train else 1.0,
        "linewidth": 1.6,
        "markersize": 4,
    }


def plot(records, panels, x_key, out_path, agg="mean", title=None, show=False):
    keys = list(metric_keys(records, x_key))
    fig, axes = plt.subplots(1, len(panels), figsize=(6.5 * len(panels), 5.5),
                             squeeze=False)

    for ax, (panel_title, pattern) in zip(axes[0], panels):
        rx = re.compile(pattern, re.I)
        matched = [k for k in keys if rx.search(k)]
        families = sorted({base_name(k) for k in matched})
        for index, key in enumerate(matched):
            data = collect(records, key, x_key, agg)
            if not data:
                continue
            ax.plot(list(data), list(data.values()),
                    label=key.replace("_epoch", ""),
                    **style_for(key, index, families))
        ax.set_title(panel_title)
        ax.set_xlabel(x_key.capitalize())
        ax.grid(True, alpha=0.3)
        # epochs are integers -- don't let matplotlib label them 2.5, 7.5
        if all(float(r[x_key]).is_integer() for r in records):
            ax.xaxis.set_major_locator(MaxNLocator(integer=True))
        if matched:
            ax.legend(fontsize=8, ncol=2)
        if re.search(r"acc", panel_title, re.I):
            ax.set_ylim(0, 1)
        if re.search(r"\blr\b|learning", panel_title, re.I):
            ax.set_yscale("log")

    axes[0][0].set_ylabel(panels[0][0])
    if title:
        fig.suptitle(title, fontsize=13)
    fig.tight_layout()
    fig.savefig(out_path, dpi=150)
    print(f"saved: {out_path}")
    if show:
        plt.show()


# --------------------------------------------------------------------------


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("log", type=Path)
    ap.add_argument("-o", "--out", type=Path, default=None)
    ap.add_argument("-x", "--x", default="epoch",
                    help="x-axis key, e.g. epoch or global_step (default: epoch)")
    ap.add_argument("--panel", action="append", default=[],
                    metavar="TITLE:REGEX",
                    help="panel spec, repeatable; default auto-detects")
    ap.add_argument("--agg", default="mean", choices=["mean", "last", "max", "min"],
                    help="how to fold per-step metrics into one x point")
    ap.add_argument("--title", default=None)
    ap.add_argument("--font", default="Times New Roman")
    ap.add_argument("--x1", action="store_true",
                    help="shift a 0-based x axis to start at 1")
    ap.add_argument("--list", action="store_true",
                    help="print discovered metric keys and exit")
    ap.add_argument("--show", action="store_true")
    args = ap.parse_args()

    records = parse(args.log, args.x)
    if not records:
        raise SystemExit(
            f"no records with '{args.x}=' found in {args.log}. "
            f"Try --x global_step, or --list against another key."
        )
    print(f"parsed {len(records)} records from {args.log}")

    if args.list:
        for key, count in metric_keys(records, args.x).items():
            print(f"  {key:<32} {count} records")
        return

    if args.x1:
        for rec in records:
            rec[args.x] += 1

    if not args.show:
        matplotlib.use("Agg")
    use_font(args.font)

    panels = []
    for spec in args.panel:
        if ":" not in spec:
            raise SystemExit(f"bad --panel {spec!r}, expected TITLE:REGEX")
        title, pattern = spec.split(":", 1)
        panels.append((title, pattern))
    panels = panels or auto_panels(metric_keys(records, args.x))

    out = args.out or args.log.with_name(args.log.stem + "_chart.png")
    plot(records, panels, args.x, out, agg=args.agg, title=args.title, show=args.show)


if __name__ == "__main__":
    main()
