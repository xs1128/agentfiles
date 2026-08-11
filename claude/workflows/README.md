# Agent Workflows

Multi-agent orchestration pipelines for common development tasks.

## Available Workflows

### `plan-build-review`
**Standard development cycle** - Plan, implement, and review

```
/workflow plan-build-review "Add user profile page"
```

Steps:
1. Planner creates implementation plan
2. Builder implements the plan
3. Reviewer checks for bugs/style

### `plan-build`
**Fast implementation** - Plan then build (no review)

```
/workflow plan-build "Fix navigation bug"
```

Steps:
1. Planner creates implementation plan
2. Builder implements the plan

### `scout-flow`
**Deep exploration** - Multi-angle scout recon, run in parallel

```
/workflow scout-flow "How does authentication work?"
```

Steps (1-3 dispatch concurrently):
1. Scout maps structure and ownership
2. Scout traces dependencies and call sites
3. Scout finds edge cases and gotchas
4. Scout merges the three reports, deduplicating and flagging contradictions

### `plan-review-plan`
**Iterative planning** - Plan, critique, refine

```
/workflow plan-review-plan "Design caching layer"
```

Steps:
1. Planner creates detailed plan
2. Plan-reviewer critiques and finds gaps
3. Planner revises based on feedback

### `full-review`
**End-to-end** - Scout, plan, build, review

```
/workflow full-review "Implement search functionality"
```

Steps:
1. Scout explores codebase
2. Planner creates plan based on findings
3. Builder implements
4. Reviewer checks quality

### `build-review-loop`
**Iterative refinement** - Build and review until approved

```
/workflow build-review-loop "Add error boundary"
```

Steps:
1. Builder implements
2. Reviewer reviews
3. Loop until reviewer approves (max 5 iterations)

## Variable Substitution

Workflows support variable substitution:
- `$INPUT` - Output from previous step
- `$ORIGINAL` - Initial task description
- `$STEP_<n>` - Output from specific step

## Creating Custom Workflows

Add to `agent-pipelines.yaml`:

```yaml
my-workflow:
  description: "What it does"
  steps:
    - agent: scout
      prompt: "Explore: $INPUT"
    - agent: builder
      prompt: "Build based on:\n\n$INPUT"
    - agent: reviewer
      prompt: "Review:\n\n$INPUT"
      loop: true
      loop_condition: "until approved"
```

## Parallel Behavior

When `parallel: true`, the workflow's steps have no dependency on one another and
are dispatched concurrently in a single message rather than one per turn. Parallel
steps read `$ORIGINAL` (there is no previous step, so `$INPUT` is unavailable).

An optional `merge` block then runs once every parallel step has returned, reading
their outputs as `$STEP_1`, `$STEP_2`, and so on in step order:

```yaml
my-parallel-workflow:
  description: "What it does"
  parallel: true
  steps:
    - agent: scout
      prompt: "First angle on: $ORIGINAL"
    - agent: scout
      prompt: "Second angle on: $ORIGINAL"
  merge:
    agent: scout
    prompt: "Reconcile:\n\n$STEP_1\n\n$STEP_2"
```

## Loop Behavior

When `loop: true`:
- Repeats the step until output contains "approved" or "satisfied"
- Maximum 5 iterations to prevent infinite loops
- Useful for build-review cycles

## Agent Types

- `scout` - Fast codebase exploration
- `planner` - Implementation planning
- `plan-reviewer` - Plan critique and validation
- `builder` - Code implementation
- `reviewer` - Code review and quality checks
