package main

import (
	"bufio"
	"errors"
	"io"
	"os/exec"
	"strings"
	"syscall"

	tea "github.com/charmbracelet/bubbletea"
)

// lineMsg is one line of script output. doneMsg ends the stream.
type lineMsg string

type doneMsg struct {
	code int
	err  error
}

// runner streams a child process's combined output as tea.Msgs.
type runner struct {
	cmd  *exec.Cmd
	out  chan string
	done chan doneMsg
}

func newRunner(dir, script string, args []string) *runner {
	cmd := exec.Command("bash", append([]string{script}, args...)...)
	cmd.Dir = dir
	// The scripts colour their own output unconditionally, but they may consult
	// TERM; give them one that supports the 256-colour codes they emit.
	cmd.Env = append(cmd.Environ(), "TERM=xterm-256color")
	return &runner{
		cmd:  cmd,
		out:  make(chan string, 256),
		done: make(chan doneMsg, 1),
	}
}

// start launches the process and returns a Cmd yielding its first message.
func (r *runner) start() tea.Cmd {
	stdout, err := r.cmd.StdoutPipe()
	if err != nil {
		return func() tea.Msg { return doneMsg{code: 1, err: err} }
	}
	r.cmd.Stderr = r.cmd.Stdout // interleave warn/fail with the ok lines

	if err := r.cmd.Start(); err != nil {
		return func() tea.Msg { return doneMsg{code: 1, err: err} }
	}

	go r.pump(stdout)
	return r.next()
}

func (r *runner) pump(stdout io.ReadCloser) {
	scanner := bufio.NewScanner(stdout)
	// Long single-line paths are routine here; raise the cap rather than have
	// Scan() stop early and silently truncate the run.
	scanner.Buffer(make([]byte, 0, 64*1024), 1024*1024)
	for scanner.Scan() {
		r.out <- strings.TrimRight(scanner.Text(), "\r")
	}

	err := r.cmd.Wait()
	code := 0
	if err != nil {
		code = 1
		var exitErr *exec.ExitError
		if errors.As(err, &exitErr) {
			if status, ok := exitErr.Sys().(syscall.WaitStatus); ok {
				code = status.ExitStatus()
			}
			// A non-zero exit is doctor.sh reporting drift, not a failure to
			// run it; don't surface it as a Go error.
			err = nil
		}
	}
	r.done <- doneMsg{code: code, err: err}

	// Closed last, so next() can drain every buffered line before reading done.
	close(r.out)
}

// next blocks for the following line, or for the exit status once out is closed.
func (r *runner) next() tea.Cmd {
	return func() tea.Msg {
		if line, ok := <-r.out; ok {
			return lineMsg(line)
		}
		return <-r.done
	}
}
