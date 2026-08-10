package main

import (
	"strings"
	"testing"

	tea "github.com/charmbracelet/bubbletea"
)

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

// Space once toggled m.agents on every multi-select step: components were
// untickable, and rows past agents' length panicked.
func TestSpaceTogglesTheStepsOwnList(t *testing.T) {
	m := newModel(".")
	m.step = stepComponents
	if !m.isMulti() || !strings.Contains(m.stepKind(), "multi") {
		t.Fatal("components should be multi-select")
	}

	for i := range m.components {
		m.cursor[int(stepComponents)] = i
		was := m.components[i].on
		next, _ := m.onKey(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune(" ")})
		m = next.(model)
		if m.components[i].on == was {
			t.Errorf("space on component %q did not toggle it", m.components[i].label)
		}
	}
	for i, a := range newModel(".").agents {
		if m.agents[i].on != a.on {
			t.Errorf("ticking components changed agent %q", a.label)
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
// this mutates the caller's list: same reason toggleSingle works.
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

func components(t *testing.T, m *model, labels ...string) {
	t.Helper()
	for i := range m.components {
		m.components[i].on = false
		for _, label := range labels {
			if m.components[i].label == label {
				m.components[i].on = true
			}
		}
	}
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
		want: "./doctor.sh --claude --config",
	}, {
		name:   "glm reaches install.sh when claude is ticked",
		agents: []string{"--claude"}, profile: "glm", action: "install",
		want: "./install.sh --claude --config --profile glm",
	}, {
		name:   "glm is dropped when claude is not ticked",
		agents: []string{"--codex", "--pi"}, profile: "glm", action: "install",
		want: "./install.sh --codex --pi --config",
	}, {
		name:   "--dry-run is appended last",
		agents: []string{"--claude"}, profile: "glm", action: "dry run",
		want: "./install.sh --claude --config --profile glm --dry-run",
	}, {
		name:   "every ticked agent is passed in one run",
		agents: []string{"--claude", "--codex", "--pi"}, profile: "native", action: "install",
		want: "./install.sh --claude --codex --pi --config",
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

func TestComponentsAreExplicitOptIns(t *testing.T) {
	m := wizard(t, []string{"--claude"}, "native", "install")
	components(t, &m, "config", "skills", "mcp")
	script, args := m.command()
	if got := strings.TrimSpace(script + " " + strings.Join(args, " ")); got != "./install.sh --claude --config --skills --mcp" {
		t.Errorf("command() = %q", got)
	}
}

// Profiles are a Claude-only concept, so the step is skipped in both directions
// when claude is unticked: otherwise the wizard offers a no-op screen.
func TestProfileStepSkippedWithoutClaude(t *testing.T) {
	for _, tc := range []struct {
		claude     bool
		from, want step
	}{
		{true, stepComponents, stepProfile},
		{false, stepComponents, stepAction},
		{true, stepAction, stepProfile},
		{false, stepAction, stepComponents},
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
	if got := strings.Join(args, " "); got != "--claude --config --profile glm" {
		t.Errorf("command() args = %q, want the profile still applied", got)
	}
}
