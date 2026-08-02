import { Skill, SkillInput } from '@anthropic-ai/skill-library';
import * as fs from 'fs';
import * as yaml from 'js-yaml';

interface WorkflowStep {
  agent: string;
  prompt: string;
  loop?: boolean;
  loop_condition?: string;
}

interface Workflow {
  description: string;
  steps: WorkflowStep[];
}

interface WorkflowConfig {
  [name: string]: Workflow;
}

export class WorkflowSkill extends Skill {
  name = 'workflow';
  description = 'Execute multi-agent workflows from YAML configuration';

  async execute(input: SkillInput) {
    const args = this.parseArgs(input.text);
    if (!args.workflowName || !args.task) {
      return this.showUsage();
    }

    const workflow = await this.loadWorkflow(args.workflowName);
    if (!workflow) {
      return `Error: Workflow "${args.workflowName}" not found.`;
    }

    return this.executeWorkflow(workflow, args.task);
  }

  private parseArgs(text: string): { workflowName?: string; task?: string } {
    const parts = text.trim().split(/\s+/);
    if (parts.length < 2) return {};

    return {
      workflowName: parts[0],
      task: parts.slice(1).join(' ')
    };
  }

  private async loadWorkflow(name: string): Promise<Workflow | null> {
    try {
      const configPath = `${process.env.HOME}/.claude/workflows/agent-pipelines.yaml`;
      const fileContents = fs.readFileSync(configPath, 'utf8');
      const config = yaml.load(fileContents) as WorkflowConfig;

      return config[name] || null;
    } catch (error) {
      console.error('Error loading workflow:', error);
      return null;
    }
  }

  private async executeWorkflow(workflow: Workflow, task: string): Promise<string> {
    let currentInput = task;
    const originalInput = task;
    const results: string[] = [];

    results.push(`\n🔄 Executing workflow: ${workflow.description}\n`);

    for (let i = 0; i < workflow.steps.length; i++) {
      const step = workflow.steps[i];
      const stepNumber = i + 1;

      results.push(`\n--- Step ${stepNumber}: ${step.agent} ---\n`);

      // Replace variables
      let prompt = step.prompt
        .replace(/\$INPUT/g, currentInput)
        .replace(/\$ORIGINAL/g, originalInput);

      // Execute agent
      const agent = this.getAgent(step.agent);
      if (!agent) {
        return `Error: Agent "${step.agent}" not found.`;
      }

      const output = await agent.execute(prompt);
      currentInput = output;
      results.push(output);

      // Handle looping
      if (step.loop) {
        let loopCount = 0;
        const maxLoops = 5;

        while (loopCount < maxLoops) {
          loopCount++;
          results.push(`\n--- Loop iteration ${loopCount} ---\n`);

          // Check loop condition (for now, just check if output contains "approved" or "satisfied")
          if (this.isApproved(currentInput)) {
            results.push('✅ Loop condition satisfied');
            break;
          }

          // Re-run with reviewer feedback
          const reviewPrompt = prompt.replace(/\$INPUT/g, currentInput);
          const reviewOutput = await agent.execute(reviewPrompt);
          currentInput = reviewOutput;
          results.push(reviewOutput);
        }

        if (loopCount >= maxLoops) {
          results.push('\n⚠️  Maximum loop iterations reached');
        }
      }
    }

    results.push(`\n✅ Workflow complete\n`);

    return results.join('\n');
  }

  private getAgent(agentName: string): any {
    // Map agent names to actual agent implementations
    const agentMap: { [name: string]: any } = {
      'planner': { execute: (prompt: string) => this.spawnAgent('planner', prompt) },
      'builder': { execute: (prompt: string) => this.spawnAgent('builder', prompt) },
      'reviewer': { execute: (prompt: string) => this.spawnAgent('reviewer', prompt) },
      'scout': { execute: (prompt: string) => this.spawnAgent('scout', prompt) },
      'plan-reviewer': { execute: (prompt: string) => this.spawnAgent('plan-reviewer', prompt) },
    };

    return agentMap[agentName];
  }

  private async spawnAgent(agentType: string, prompt: string): Promise<string> {
    // This would spawn the actual agent using the Agent tool
    // For now, return a placeholder
    return `[Agent ${agentType} output for: ${prompt.substring(0, 50)}...]`;
  }

  private isApproved(output: string): boolean {
    const approved = /approved|satisfied|good|pass|✅/i.test(output);
    const rejected = /needs improvement|fix|change|issues|❌/i.test(output);
    return approved && !rejected;
  }

  private showUsage(): string {
    return `
Usage: /workflow <workflow-name> <task-description>

Available workflows:
  - plan-build-review: Plan, build, and review
  - plan-build: Plan then build (fast)
  - scout-flow: Triple-scout deep exploration
  - plan-review-plan: Iterative planning
  - full-review: Scout → Plan → Build → Review
  - build-review-loop: Build and review iteratively

Examples:
  /workflow plan-build-review "Implement user authentication"
  /workflow scout-flow "Find all API endpoints"
  /workflow build-review-loop "Add dark mode toggle"
`;
  }
}
