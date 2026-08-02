# Workflow Executor

Execute multi-agent workflows defined in `.claude/workflows/agent-pipelines.yaml`.

## Usage

```
/workflow <workflow-name> <task-description>
```

## Available Workflows

- `plan-build-review` - Plan, build, review (standard cycle)
- `plan-build` - Plan then build (fast, no review)
- `scout-flow` - Triple-scout deep exploration
- `plan-review-plan` - Iterative planning with critique
- `full-review` - Scout → Plan → Build → Review
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

## Variable Substitution

- `$INPUT` - Output from previous step
- `$ORIGINAL` - Initial task description
- `$STEP_<n>` - Output from specific step number
