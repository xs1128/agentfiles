//go:build !windows

package main

import (
	"os/exec"
	"syscall"
)

func setPgid(cmd *exec.Cmd) { cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true} }

func killGroup(pid int) { _ = syscall.Kill(-pid, syscall.SIGTERM) }
