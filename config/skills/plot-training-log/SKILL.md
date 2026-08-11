---
name: plot-training-log
description: >
  Parse a machine-learning training log (.out/.log/.err) and plot epoch-vs-metric line
  charts (折線圖) with a Python script -- accuracy curves, loss curves, learning-rate
  schedules, train-vs-validation overfitting checks. Handles `rich`-formatted logs whose
  metric records are soft-wrapped across many lines with timestamp and `trainer.py:233`
  columns. Times New Roman by default.
  Triggers on: "plot the training log", "chart the loss", "graph epoch vs accuracy",
  "折線圖", "plot loss curve", "visualize training metrics", "make a chart from this .out",
  "did it overfit", "training curve", "plot val accuracy", "/plot-training-log".
allowed-tools: Read Bash Write Edit
---

# plot-training-log: training log → line chart

`scripts/plot_training_log.py` does the whole job. Read the log's shape first,
then drive the script. Don't hand-write a new parser per log — extend this one.

## Workflow

**1. Look at the log before parsing.** `head -40` and `tail -40`. You are
checking two things: which metric keys exist, and whether records are
soft-wrapped by `rich`.

**2. Discover the metric keys.** Never guess them:

```bash
python scripts/plot_training_log.py train.out --list
```

Prints every `key=value` metric found and how many records carry it. If it
reports `no records with 'epoch=' found`, retry with `--x global_step` or
`--x step`. If it still finds nothing, the file probably isn't a training log
(serving/data-prep logs in the same directory often aren't).

**3. Plot.** Auto-panels (Accuracy / Loss / Learning rate) need no flags:

```bash
python scripts/plot_training_log.py train.out --x1 -o chart.png
```

Explicit panels when you want control — `--panel "TITLE:REGEX"`, repeatable,
one panel per flag:

```bash
python scripts/plot_training_log.py train.out --x1 \
  --panel "Validation accuracy:^val/.*acc" \
  --panel "Loss:loss_\d" \
  --title "EAGLE-3 draft model" -o chart.png
```

**4. Read the chart back** with the Read tool and check it before reporting.
Then state what the curves actually show (best epoch, overfitting gap), not
just "chart saved".

## Flags

| Flag | Purpose |
|---|---|
| `--list` | print discovered metric keys, exit |
| `--x KEY` | x-axis key: `epoch` (default), `global_step`, `step` |
| `--x1` | shift a 0-based axis to start at 1 (trainers log `epoch=0` for epoch 1) |
| `--panel "T:RE"` | one panel; repeat for more; default auto-detects |
| `--agg` | fold per-step metrics into one x point: `mean` (default), `last`, `max`, `min` |
| `--font` | default `Times New Roman`, falls back through Times clones then serif |
| `--title`, `-o`, `--show` | figure title, output path, interactive window |

## Encoding conventions

The script styles curves so a reader can decode them without reading labels:

- **color** = head/index parsed off the key tail (`loss_0`, `loss_1`, `loss_2`)
- **dashed + faded** = train, **solid + markers** = val/eval/test
- **marker shape** = metric family (`full_acc` vs `cond_acc`) within a panel
- accuracy panels clamp to `ylim 0-1`; learning-rate panels go log-scale
- integer x ticks when all x values are integral (no `epoch=2.5`)

## Gotchas that cost real time

**`rich` soft-wrap.** One metrics record spans ~10 physical lines, with a
timestamp column left and `trainer.py:233` right. Line-by-line parsing gets
you fragments. The script strips both columns, drops progress-bar lines, and
joins the file into one stream before matching.

**`epoch=` matches inside key names.** Validation keys look like
`val/full_acc_0_epoch=0.537`. A naive `epoch=\d+` record boundary matches the
`epoch=0` *inside that key*, truncating every val record — you get zero val
data and a chart that silently shows train only. The `(?<!\w)` lookbehind is
load-bearing. If val curves are missing, check this first.

**Aggregation asymmetry.** Train metrics are logged per step (thousands of
records), val metrics per epoch (one record). `--agg mean` folds train down to
one point per epoch so the two overlay honestly. Don't compare a per-step
train curve against a per-epoch val curve on the same axis without folding.

**matplotlib install.** System Python on macOS is PEP 668 externally managed —
`pip install matplotlib` fails. Make a venv next to the logs:

```bash
python3 -m venv .venv && .venv/bin/pip install matplotlib
.venv/bin/python scripts/plot_training_log.py train.out
```

The download can take several minutes on a slow link; run it in the background
and poll rather than assuming it hung.

## Extending

New log format: adjust `PREFIX` / `SUFFIX` / `PROGRESS` in the flattening
section. New metric layout: `KEY` and `KV` regexes. New default panel family:
append to `AUTO_PANELS`. Keep the script one file with no deps beyond
matplotlib.
