package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// missingDeps consults PATH, so point PATH at a directory holding only the
// binaries a case wants to exist. Every other name then reads as missing.
func pathWith(t *testing.T, bins ...string) {
	t.Helper()
	dir := t.TempDir()
	for _, bin := range bins {
		script := filepath.Join(dir, bin)
		if err := os.WriteFile(script, []byte("#!/bin/sh\n"), 0o755); err != nil {
			t.Fatalf("stub %s: %v", bin, err)
		}
	}
	t.Setenv("PATH", dir)
}

func TestMissingDepsIsPerAgent(t *testing.T) {
	cases := []struct {
		name    string
		present []string
		agents  []string
		want    string
	}{{
		name:    "codex alone does not ask for claude's toolchain",
		present: []string{"git", "python3", "jq", "codex", "rtk"},
		agents:  []string{"--codex"},
		want:    "",
	}, {
		name:    "codex alone still reports its own tools",
		present: []string{"git", "python3", "jq"},
		agents:  []string{"--codex"},
		want:    "codex,rtk",
	}, {
		name:    "claude needs bun, codex does not",
		present: []string{"git", "python3", "jq", "claude", "codex", "rtk"},
		agents:  []string{"--claude", "--codex"},
		want:    "bun",
	}, {
		name:    "rtk is reported once when both agents want it",
		present: []string{"git", "python3", "jq", "claude", "bun", "codex"},
		agents:  []string{"--claude", "--codex"},
		want:    "rtk",
	}, {
		name:    "required tools are reported with no agent selected",
		present: []string{"python3", "jq"},
		agents:  nil,
		want:    "git",
	}}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			pathWith(t, tc.present...)
			if got := strings.Join(missingDeps(tc.agents), ","); got != tc.want {
				t.Errorf("missingDeps(%v) = %q, want %q", tc.agents, got, tc.want)
			}
		})
	}
}

// The agents step is the only multi-select, and the whole point of the marker
// shapes is that it reads as one before the user presses space to find out.
func TestAgentsStepReadsAsMultiSelect(t *testing.T) {
	m := newModel(".")

	m.step = stepAgents
	if !strings.Contains(m.stepKind(), "multi") {
		t.Errorf("agents step kind = %q, want it to say multi", m.stepKind())
	}
	if got := m.mark(true); got != sOn.Render("[x]") {
		t.Errorf("ticked agent mark = %q, want a square checkbox", got)
	}

	for _, s := range []step{stepProfile, stepAction} {
		m.step = s
		if strings.Contains(m.stepKind(), "multi") {
			t.Errorf("step %d kind = %q, want it to say pick one", s, m.stepKind())
		}
		if got := m.mark(false); got != "( )" {
			t.Errorf("step %d unticked mark = %q, want a round radio", s, got)
		}
	}
}

// The multi-select step has nothing to go back to, so offering "esc back"
// there would point at a no-op.
func TestKeyHintsMatchWhatTheStepAccepts(t *testing.T) {
	m := newModel(".")

	m.step = stepAgents
	if !strings.Contains(m.keyHints(), "tick") {
		t.Errorf("agents hints = %q, want them to mention ticking", m.keyHints())
	}
	if strings.Contains(m.keyHints(), "esc") {
		t.Errorf("agents hints = %q, but esc is a no-op on the first step", m.keyHints())
	}

	m.step = stepAction
	if !strings.Contains(m.keyHints(), "esc back") {
		t.Errorf("action hints = %q, want esc back offered", m.keyHints())
	}
}

// pick turns a radio list into the named choice. The slice header is shared, so
// this mutates the caller's list — same reason toggleSingle works.
func pick(t *testing.T, list []choice, label string) {
	t.Helper()
	found := false
	for i := range list {
		list[i].on = list[i].label == label
		found = found || list[i].label == label
	}
	if !found {
		t.Fatalf("no choice labelled %q", label)
	}
}

func wizard(t *testing.T, agents []string, profile, action string) model {
	t.Helper()
	m := newModel(".")
	for i := range m.agents {
		m.agents[i].on = false
		for _, want := range agents {
			if m.agents[i].key == want {
				m.agents[i].on = true
			}
		}
	}
	pick(t, m.profile, profile)
	pick(t, m.action, action)
	return m
}

// command() is the wizard's whole contract: it reproduces the CLI surface, and
// the confirm line shows exactly what will run.
func TestCommandReproducesTheCLISurface(t *testing.T) {
	cases := []struct {
		name    string
		agents  []string
		profile string
		action  string
		want    string
	}{{
		name:   "doctor drops --profile, which it does not accept",
		agents: []string{"--claude"}, profile: "glm", action: "doctor",
		want: "./doctor.sh --claude",
	}, {
		name:   "glm reaches install.sh when claude is ticked",
		agents: []string{"--claude"}, profile: "glm", action: "install",
		want: "./install.sh --claude --profile glm",
	}, {
		name:   "glm is dropped when claude is not ticked",
		agents: []string{"--codex", "--pi"}, profile: "glm", action: "install",
		want: "./install.sh --codex --pi",
	}, {
		name:   "--dry-run is appended last",
		agents: []string{"--claude"}, profile: "glm", action: "dry run",
		want: "./install.sh --claude --profile glm --dry-run",
	}, {
		name:   "every ticked agent is passed in one run",
		agents: []string{"--claude", "--codex", "--pi"}, profile: "native", action: "install",
		want: "./install.sh --claude --codex --pi",
	}}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			m := wizard(t, tc.agents, tc.profile, tc.action)
			script, args := m.command()
			got := strings.TrimSpace(script + " " + strings.Join(args, " "))
			if got != tc.want {
				t.Errorf("command() = %q, want %q", got, tc.want)
			}
		})
	}
}

// Profiles are a Claude-only concept, so the step is skipped in both directions
// when claude is unticked — otherwise the wizard offers a no-op screen.
func TestProfileStepSkippedWithoutClaude(t *testing.T) {
	for _, tc := range []struct {
		claude     bool
		from, want step
	}{
		{true, stepAgents, stepProfile},
		{false, stepAgents, stepAction},
		{true, stepAction, stepProfile},
		{false, stepAction, stepAgents},
	} {
		agents := []string{"--codex"}
		if tc.claude {
			agents = append(agents, "--claude")
		}
		m := wizard(t, agents, "native", "install")
		m.step = tc.from
		got := m.next()
		if tc.from == stepAction {
			got = m.prev()
		}
		if got != tc.want {
			t.Errorf("claude=%v from step %d: got step %d, want %d", tc.claude, tc.from, got, tc.want)
		}
	}
}

// claudeSelected gates the profile step. It used to read m.agents[0], so this
// locks in that the lookup is by key and the slice may be reordered freely.
func TestClaudeSelectedSurvivesAgentReorder(t *testing.T) {
	m := wizard(t, []string{"--claude"}, "glm", "install")
	m.agents = []choice{m.agents[2], m.agents[1], m.agents[0]} // claude now last

	if !m.claudeSelected() {
		t.Fatal("claudeSelected() = false after reordering, want true")
	}
	_, args := m.command()
	if got := strings.Join(args, " "); got != "--claude --profile glm" {
		t.Errorf("command() args = %q, want the profile still applied", got)
	}
}

// The wizard passes these exact strings to install.sh; a typo here would
// silently skip an agent's dependency check.
func TestAgentDepsKeysMatchWizardFlags(t *testing.T) {
	for _, c := range newModel(".").agents {
		if _, ok := agentDeps[c.key]; !ok {
			t.Errorf("agent %q offers flag %q with no agentDeps entry", c.label, c.key)
		}
	}
}
