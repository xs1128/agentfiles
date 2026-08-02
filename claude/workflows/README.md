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
**Deep exploration** - Triple-scout investigation

```
/workflow scout-flow "How does authentication work?"
```

Steps:
1. Scout explores codebase
2. Scout validates findings
3. Scout verifies completeness

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
