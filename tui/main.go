// Command agent-config-tui is the interactive front-end for install.sh and
// doctor.sh.
//
// It owns no installation logic. It collects the flags a human would otherwise
// have to remember, then shells out to the same bash scripts that run headless
// and in CI, streaming their output back. If this binary will not build, every
// action it offers is still reachable by hand:
//
//	./install.sh --claude --profile glm
//	./doctor.sh --claude
package main

import (
	"errors"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
)

func main() {
	repo := flag.String("repo", "", "path to the agent-config checkout (default: git root of cwd)")
	flag.Parse()

	root, err := resolveRepo(*repo)
	if err != nil {
		fmt.Fprintf(os.Stderr, "agent-config: %v\n", err)
		os.Exit(1)
	}

	// The wizard is a full-screen alt-buffer app; the streamed script output
	// stays inside a viewport rather than scrolling the user's scrollback.
	p := tea.NewProgram(newModel(root), tea.WithAltScreen())
	final, err := p.Run()
	if err != nil {
		fmt.Fprintf(os.Stderr, "agent-config: %v\n", err)
		os.Exit(1)
	}

	// Propagate doctor's verdict: `./tui/run.sh && deploy` should behave like
	// `./doctor.sh && deploy`.
	if m, ok := final.(model); ok {
		os.Exit(m.exitCode)
	}
}

// resolveRepo finds the checkout. An explicit --repo wins; otherwise walk up
// from the cwd looking for the marker files, which also covers being invoked
// from a subdirectory.
func resolveRepo(explicit string) (string, error) {
	if explicit != "" {
		abs, err := filepath.Abs(explicit)
		if err != nil {
			return "", err
		}
		return abs, validateRepo(abs)
	}

	dir, err := os.Getwd()
	if err != nil {
		return "", err
	}
	for {
		if validateRepo(dir) == nil {
			return dir, nil
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			break
		}
		dir = parent
	}
	return "", errors.New("not inside an agent-config checkout — pass --repo /path/to/agent-config")
}

func validateRepo(dir string) error {
	for _, want := range []string{"install.sh", "doctor.sh", "lib/common.sh"} {
		if _, err := os.Stat(filepath.Join(dir, want)); err != nil {
			return fmt.Errorf("%s is not an agent-config checkout (missing %s)", dir, want)
		}
	}
	return nil
}

// have reports whether a binary is on PATH. Used only to warn — the scripts
// themselves do the authoritative dependency check via shared/manifests/deps.json.
func have(bin string) bool {
	_, err := exec.LookPath(bin)
	return err == nil
}

// agentDeps mirrors perAgent in shared/manifests/deps.json. Keyed by the same
// flag the wizard passes to install.sh, so a new agent needs one entry here and
// one choice in newModel.
var agentDeps = map[string][]string{
	"--claude": {"claude", "rtk", "bun"},
	"--codex":  {"codex", "rtk"},
	"--pi":     {"pi"},
}

// missingDeps reports which tools the *currently selected* agents need and the
// host lacks. Warning only, and deliberately recomputed as the selection
// changes — check_deps in lib/deps.sh is the authoritative gate.
func missingDeps(agentFlags []string) []string {
	want := []string{"git", "python3", "jq"} // deps.json "required"
	for _, flag := range agentFlags {
		want = append(want, agentDeps[flag]...)
	}

	var missing []string
	seen := map[string]bool{}
	for _, bin := range want {
		if seen[bin] {
			continue // rtk is shared by claude and codex
		}
		seen[bin] = true
		if !have(bin) {
			missing = append(missing, bin)
		}
	}
	return missing
}

func joinArgs(args []string) string { return strings.Join(args, " ") }
