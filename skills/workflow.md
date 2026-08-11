# Workflow Executor

Execute multi-agent workflows defined in `.claude/workflows/agent-pipelines.yaml`.

## Usage

```
/workflow <workflow-name> <task-description>
```

## Available Workflows

- `plan-build-review` - Plan, build, review (standard cycle)
- `plan-build` - Plan then build (fast, no review)
- `scout-flow` - Multi-angle recon, three scouts in parallel
- `plan-review-plan` - Iterative planning with critique
- `full-review` - Parallel recon, then plan, build, review
- `build-review-loop` - Build and review iteratively until approved

## Examples

```
/workflow plan-build-review "Implement user authentication"
/workflow scout-flow "Find all API endpoints"
/workflow build-review-loop "Add dark mode toggle"
```

## Implementation

When user invokes `/workflow`:
1. Parse workflow name and task description
2. Load workflow from `.claude/workflows/agent-pipelines.yaml`
3. Execute each step sequentially
4. Pass `$INPUT` (output from previous step) to next agent
5. Preserve `$ORIGINAL` (initial task description)
6. If `loop: true`, repeat builder → reviewer until approved
7. Return final output

### Parallel workflows

If the workflow sets `parallel: true`, its `steps` have no dependency on each
other and must be dispatched **concurrently**: every Task call in a single
message, not one per turn. Parallel steps cannot reference `$INPUT` (there is no
previous step); they take `$ORIGINAL` instead.

A `parallel` workflow may then define a single `merge` step, which runs after all
parallel steps return and reads their outputs as `$STEP_1`, `$STEP_2`, … in step
order. Its output is the workflow's output.

A sequential workflow can also contain a `parallel:` block as one of its steps.
Dispatch everything inside that block concurrently, wait once, and concatenate the
results into that step's `$STEP_n`. The block counts as one step for numbering.

### Do not make an agent re-earn what a previous one found

`$INPUT` is only the previous step's output, so forwarding it alone throws away
everything found earlier in the pipeline. Use `$STEP_n` to hand each agent the
artifacts it actually needs: builder wants both the plan and the recon that plan
was written from, so it can open the named files directly instead of searching for
them again.

Reviewers are the exception: give a reviewer the diff, not a description of it.
`git diff` is cheaper and more trustworthy than the builder's own account of what
it changed.

## Variable Substitution

- `$INPUT` - Output from previous step
- `$ORIGINAL` - Initial task description
- `$STEP_<n>` - Output from specific step number
