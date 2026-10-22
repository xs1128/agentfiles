# Report refinement and delivery

Read when drafting or revising prose, evaluating feedback, adding evidence, exporting, or organizing final files. Typography and layout defaults are in [style.md](style.md).

## Short without losing coverage

Build around what the reader must assess. An experimental section usually keeps method, measured result, interpretation, and material limitation. Prefer a compact table or labeled figure over dense paragraphs of flags and numbers. Explain individual command arguments only when the rubric asks.

Cut generic intros, repeated conclusions, inflated language, and the chronological debugging story. First person is fine when it accurately describes the author's work and the required style allows it. Keep uncertainty attached to the claim it limits.

Meet a page budget by removing duplication and improving presentation first. Keep the methodology needed to interpret timing boundaries, memory scope, controls, and aggregation. If required evidence cannot fit legibly, state the tradeoff instead of shrinking everything or silently dropping a section.

For feedback, separate actual omissions or errors from optional strengthening. Formatting revisions must not change validated numbers, methods, or conclusions. New measurements need fresh validation and updated analysis.

## Honest, readable evidence

Prefer genuine screenshots of the requested environment showing the command and full relevant result. Label screenshots of saved logs as saved output. A browser rendering of a log is not a terminal capture. Reconstructed visuals must not imply live capture.

Crop only for readability, never to change meaning or hide relevant output. Label which environment and trial each figure shows. A single-trial screenshot need not match a median table, but labels must make that clear.

Do not put screenshot text that promises a link. If the PDF needs a hyperlink, create and verify a real one. Local raw-log links are useless to a grader who only receives the PDF.

Move long commands out of crowded prose. Use tables for parallel arguments when readable. Size screenshots for legibility at normal zoom, not just to fit a page count.

## Verify the export

After meaningful edits, inspect every rendered page:

- Layout: figure resolution, captions, table wrapping, code line breaks, margins, page breaks, spacing.
- Content: all required sections, correct values and units, consistent trial labels, required links, filename, format.

When moving files, check source references and rebuild. For a layout-preserving move, compare regenerated text, pagination, and render with the existing final. Keep raw records even when archiving earlier attempts.

Keep the final deliverable easy to find, e.g. `submission/`, one folder per part, and `archive/` for earlier attempts, adapted to existing conventions. Add a short navigation file after a big reorganization.

Hand off with the final artifact and the verification done. Mention any requirement that materially affects readiness, such as an unverified demo or inaccessible submission link. Never claim an upload happened when it did not.
