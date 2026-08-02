package main

import (
	"fmt"
	"strings"

	"github.com/charmbracelet/bubbles/viewport"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

type step int

const (
	stepAgents step = iota
	stepProfile
	stepAction
	stepRun
)

// Same palette as lib/common.sh, so the wizard chrome and the streamed script
// output read as one program.
var (
	cDim  = lipgloss.Color("240")
	cRed  = lipgloss.Color("203")
	cYel  = lipgloss.Color("220")
	cGrn  = lipgloss.Color("71")
	cBlue = lipgloss.Color("111")

	sTitle    = lipgloss.NewStyle().Bold(true)
	sDim      = lipgloss.NewStyle().Foreground(cDim)
	sSel      = lipgloss.NewStyle().Foreground(cBlue).Bold(true)
	sOn       = lipgloss.NewStyle().Foreground(cGrn)
	sWarn     = lipgloss.NewStyle().Foreground(cYel)
	sErr      = lipgloss.NewStyle().Foreground(cRed)
	sViewport = lipgloss.NewStyle().Border(lipgloss.RoundedBorder()).BorderForeground(cDim)
)

type choice struct {
	key   string
	label string
	hint  string
	on    bool
}

type model struct {
	repo string
	step step

	agents  []choice
	profile []choice
	action  []choice

	cursor [3]int // one per selection step
	warn   string

	vp       viewport.Model
	lines    []string
	run      *runner
	finished bool
	exitCode int
	runErr   error

	ready bool
}

func newModel(repo string) model {
	return model{
		repo: repo,
		agents: []choice{
			{key: "--claude", label: "claude", hint: "settings, subagents, workflows, skills, plugins", on: true},
			{key: "--codex", label: "codex", hint: "AGENTS.md, skills, merged config.toml (model, MCP, plugins)"},
			{key: "--pi", label: "pi", hint: "settings.json + rendered models.json (needs ZAI_API_KEY)"},
		},
		profile: []choice{
			{label: "native", hint: "~/.claude — Anthropic, Opus", on: true},
			{label: "glm", hint: "~/.claude-glm too — z.ai GLM, shares agents and skills"},
		},
		action: []choice{
			{label: "dry run", hint: "print every action, change nothing", on: true},
			{label: "install", hint: "link configs, fetch skills, install plugins"},
			{label: "doctor", hint: "read-only drift check; non-zero exit if drifted"},
		},
	}
}

func (m model) Init() tea.Cmd { return nil }

// selected returns the flags for every ticked agent.
func (m model) agentFlags() []string {
	var out []string
	for _, c := range m.agents {
		if c.on {
			out = append(out, c.key)
		}
	}
	return out
}

func (m model) anyAgent() bool { return len(m.agentFlags()) > 0 }

func (m model) claudeSelected() bool { return m.agents[0].on }

func (m model) profileName() string {
	for _, c := range m.profile {
		if c.on {
			return c.label
		}
	}
	return "native"
}

func (m model) actionLabel() string {
	for _, c := range m.action {
		if c.on {
			return c.label
		}
	}
	return "dry run"
}

// command turns the collected answers into the exact script invocation, which
// is also what the confirm line shows — no hidden behaviour.
func (m model) command() (string, []string) {
	args := m.agentFlags()
	if m.actionLabel() == "doctor" {
		return "./doctor.sh", args
	}
	// --profile is Claude-only and meaningless without it.
	if m.claudeSelected() && m.profileName() == "glm" {
		args = append(args, "--profile", "glm")
	}
	if m.actionLabel() == "dry run" {
		args = append(args, "--dry-run")
	}
	return "./install.sh", args
}

// toggleSingle turns a choice list into a radio group. choice is a value type
// but the slice header is shared, so this mutates the caller's list.
func toggleSingle(list []choice, idx int) {
	for i := range list {
		list[i].on = i == idx
	}
}

func atLeast(v, floor int) int {
	if v < floor {
		return floor
	}
	return v
}

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		// A terminal that reports no size (some pty wrappers, CI) would give a
		// negative width here and the viewport would silently render nothing.
		w := atLeast(msg.Width-4, 40) // 4 = the rounded border
		h := atLeast(msg.Height-8, 5) // 8 = title, command line, footer
		if !m.ready {
			m.vp = viewport.New(w, h)
			m.ready = true
		} else {
			m.vp.Width, m.vp.Height = w, h
		}
		return m, nil

	case lineMsg:
		m.lines = append(m.lines, string(msg))
		m.vp.SetContent(strings.Join(m.lines, "\n"))
		m.vp.GotoBottom()
		return m, m.run.next()

	case doneMsg:
		m.finished = true
		m.exitCode, m.runErr = msg.code, msg.err
		return m, nil

	case tea.KeyMsg:
		return m.onKey(msg)
	}

	if m.step == stepRun {
		var cmd tea.Cmd
		m.vp, cmd = m.vp.Update(msg)
		return m, cmd
	}
	return m, nil
}

func (m model) onKey(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch msg.String() {
	case "ctrl+c":
		return m, tea.Quit
	case "q":
		// While a script is running, q would strand a half-finished install;
		// only allow it once the process has exited.
		if m.step != stepRun || m.finished {
			return m, tea.Quit
		}
		return m, nil
	}

	if m.step == stepRun {
		var cmd tea.Cmd
		m.vp, cmd = m.vp.Update(msg)
		return m, cmd
	}

	list := m.list(m.step)
	idx := int(m.step)

	switch msg.String() {
	case "up", "k":
		if m.cursor[idx] > 0 {
			m.cursor[idx]--
		}
	case "down", "j":
		if m.cursor[idx] < len(list)-1 {
			m.cursor[idx]++
		}
	case " ":
		if m.step == stepAgents {
			m.agents[m.cursor[idx]].on = !m.agents[m.cursor[idx]].on
		} else {
			toggleSingle(list, m.cursor[idx])
		}
		m.warn = ""
	case "esc", "left", "h":
		m.step = m.prev()
	case "enter", "right", "l":
		if m.step != stepAgents {
			toggleSingle(list, m.cursor[idx])
		}
		if m.step == stepAgents && !m.anyAgent() {
			m.warn = "pick at least one agent (space to tick)"
			return m, nil
		}
		m.warn = ""
		next := m.next()
		m.step = next
		if next == stepRun {
			script, args := m.command()
			m.lines = []string{sDim.Render(fmt.Sprintf("$ %s %s", script, joinArgs(args)))}
			m.vp.SetContent(strings.Join(m.lines, "\n"))
			m.run = newRunner(m.repo, script, args)
			return m, m.run.start()
		}
	}
	return m, nil
}

func (m model) list(s step) []choice {
	switch s {
	case stepAgents:
		return m.agents
	case stepProfile:
		return m.profile
	default:
		return m.action
	}
}

// next/prev skip the profile step when claude is not selected — profiles are a
// Claude-only concept.
func (m model) next() step {
	switch m.step {
	case stepAgents:
		if m.claudeSelected() {
			return stepProfile
		}
		return stepAction
	case stepProfile:
		return stepAction
	default:
		return stepRun
	}
}

func (m model) prev() step {
	switch m.step {
	case stepAction:
		if m.claudeSelected() {
			return stepProfile
		}
		return stepAgents
	case stepProfile:
		return stepAgents
	default:
		return stepAgents
	}
}

func (m model) View() string {
	if !m.ready {
		return "\n  loading…\n"
	}
	if m.step == stepRun {
		return m.viewRun()
	}
	return m.viewWizard()
}

func (m model) viewWizard() string {
	var b strings.Builder

	b.WriteString(sTitle.Render("agent-config") + "  " + sDim.Render(m.repo) + "\n\n")

	// Recomputed every frame so ticking an agent on or off updates the warning
	// to that agent's tools rather than a fixed claude-shaped list.
	if deps := missingDeps(m.agentFlags()); len(deps) > 0 {
		b.WriteString(sWarn.Render("missing on PATH: "+strings.Join(deps, ", ")) + "\n")
		b.WriteString(sDim.Render("the script will tell you how to install each one") + "\n\n")
	}

	prompt := map[step]string{
		stepAgents:  "Which agents?",
		stepProfile: "Which Claude profile?",
		stepAction:  "What should I run?",
	}[m.step]
	b.WriteString(sTitle.Render(prompt) + "  " + sDim.Render(m.stepKind()) + "\n")
	b.WriteString(sDim.Render(m.stepHelp()) + "\n\n")

	list := m.list(m.step)
	for i, c := range list {
		line := fmt.Sprintf("%s %-8s %s", m.mark(c.on), c.label, sDim.Render(c.hint))
		if i == m.cursor[int(m.step)] {
			b.WriteString(sSel.Render("❯ ") + line + "\n")
		} else {
			b.WriteString("  " + line + "\n")
		}
	}

	script, args := m.command()
	b.WriteString("\n" + sDim.Render(fmt.Sprintf("→ %s %s", script, joinArgs(args))) + "\n")

	if m.warn != "" {
		b.WriteString("\n" + sWarn.Render(m.warn) + "\n")
	}

	b.WriteString("\n" + sDim.Render(m.keyHints()))
	return b.String()
}

// Only the agents step accepts more than one answer. Everything below exists so
// that is obvious before the user presses space to find out.
func (m model) isMulti() bool { return m.step == stepAgents }

func (m model) stepKind() string {
	if m.isMulti() {
		return "· multi-select"
	}
	return "· pick one"
}

func (m model) stepHelp() string {
	if m.isMulti() {
		return "space to tick — tick as many as you want, they install in one run"
	}
	return "space or enter to choose"
}

// Square boxes tick, round ones are exclusive — the same convention as a web
// form's checkboxes vs radios, so the shape alone answers "can I pick two?".
func (m model) mark(on bool) string {
	switch {
	case m.isMulti() && on:
		return sOn.Render("[x]")
	case m.isMulti():
		return "[ ]"
	case on:
		return sOn.Render("(•)")
	default:
		return "( )"
	}
}

func (m model) keyHints() string {
	if m.isMulti() {
		return "↑/↓ move · space tick/untick · enter continue · q quit"
	}
	return "↑/↓ move · space select · enter next · esc back · q quit"
}

func (m model) viewRun() string {
	script, args := m.command()
	head := sTitle.Render("running") + "  " + sDim.Render(fmt.Sprintf("%s %s", script, joinArgs(args)))

	var foot string
	switch {
	case m.runErr != nil:
		foot = sErr.Render("could not run: " + m.runErr.Error())
	case !m.finished:
		foot = sDim.Render("↑/↓ scroll · ctrl+c abort")
	case m.exitCode == 0:
		foot = sOn.Render("done") + sDim.Render("  ·  q to quit")
	default:
		foot = sErr.Render(fmt.Sprintf("exit %d", m.exitCode)) +
			sDim.Render("  ·  most problems are fixed by re-running install  ·  q to quit")
	}

	return head + "\n" + sViewport.Render(m.vp.View()) + "\n" + foot
}
