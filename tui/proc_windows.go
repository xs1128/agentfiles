//go:build windows

package main

import (
	"os"
	"os/exec"
)

// No process groups here; the child alone is what we can reach.
func setPgid(*exec.Cmd) {}

func killGroup(pid int) {
	if p, err := os.FindProcess(pid); err == nil {
		_ = p.Kill()
	}
}
