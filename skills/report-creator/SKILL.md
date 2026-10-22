---
name: report-creator
description: "Prepare or refine evidence-based coursework, lab, and technical reports, from interpreting requirements and planning experiments to analyzing results and producing a verified PDF. Use for report work tied to a specification, rubric, or real measurements, e.g. \"write the HW report\", \"lab report\", \"write up these results\"."
---

# Report Creator

Turn an assignment or technical question into a defensible report with traceable evidence and a reproducible source. Enter at the stage the user needs. Keep validated work usable through later revisions.

## Establish the target

Read the spec, rubric, required tasks, and any template before choosing experiments or sections. Open referenced pages not supplied. Separate requirements from optional improvements and user preferences.

Keep a compact coverage map (working notes or an existing project doc): requirement, method, evidence location, report section, open gap. Take filenames, formats, demo requirements, and submission conditions from the actual instructions, never from another assignment.

Inspect existing workspace and evidence before creating replacements. Ask only about gaps that change validity or scope (approved substitutions, available resources, plan-only vs full). Keep working on independent parts while waiting. A plan-only request stops at a concrete plan.

## Resolve the core problem

Choose the smallest experiment that answers each required question. Confirm environment and a working baseline before a batch. Configuration, successful execution, and proof of the claimed behavior are three different things.

For setup, measurement, troubleshooting, or analysis, read [references/experiments.md](references/experiments.md). If the user runs commands, give one checkpoint at a time, say what success looks like, and ask for the output before the next dependent step.

Stay within authorization: report editing alone does not permit restarting VMs, reinstalling tools, or rerunning benchmarks. Each troubleshooting retry tests a specific hypothesis with a bounded wait. Repeated unchanged failures mean change approach or name the missing prerequisite.

## Turn evidence into a report

Update the report source as validated results arrive. Tie every number to raw output and the method that produced it. Keep failed measurements and state limitations instead of dropping them or recording zeros. Separate observations, plausible explanations, and untested conclusions.

Read [references/report-and-delivery.md](references/report-and-delivery.md) when drafting, revising from feedback, or preparing submission files. Read [references/style.md](references/style.md) before laying out or rendering the document: it holds this user's default typography and layout.

Carry forward the user's accepted preferences for length, punctuation, alignment, code styling, screenshots, and references. Keep required attribution even when a sources section is unwanted. Humanizing prose must not change evidence or claim work the user did not do.

For grader or judge comments, check each actionable point against the instructions, source data, and rendered report, and fix demonstrated gaps proportionally.

## Finish

Keep one obvious final deliverable per required format, plus editable source, reproducible scripts, and retained evidence. Follow repo conventions. When reorganizing, preserve files and update figure links, build paths, and dependencies.

After meaningful changes, verify per the checklist in report-and-delivery.md. Use an available PDF or document skill for format mechanics.

Report what is done, where the final files are, and any material open requirement. Submission-ready is not submitted. Stop task-owned background work and report the final state of any environment you changed.
