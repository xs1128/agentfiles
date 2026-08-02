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

// The wizard passes these exact strings to install.sh; a typo here would
// silently skip an agent's dependency check.
func TestAgentDepsKeysMatchWizardFlags(t *testing.T) {
	for _, c := range newModel(".").agents {
		if _, ok := agentDeps[c.key]; !ok {
			t.Errorf("agent %q offers flag %q with no agentDeps entry", c.label, c.key)
		}
	}
}
