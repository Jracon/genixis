package main

import (
	"os"
	"slices"
	"strings"
	"testing"
)

// The stop of a per-leg harness instance carries the config directory of
// that instance (the review of pull request 615): the variable is set, never
// appended, so a caller that already names an instance cannot shadow a call
// that targets another one.
func TestHarnessEnvSetsTheConfigDir(t *testing.T) {
	t.Setenv("CLAUDE_CONFIG_DIR", "/home/dev/.claude")
	t.Setenv("HOME", "/home/dev")
	env := harnessEnv("/home/dev/projects/genixis/.claude-legs/ai-issue-607/config")
	var configDir string
	count := 0
	for _, entry := range env {
		if strings.HasPrefix(entry, "CLAUDE_CONFIG_DIR=") {
			count++
			configDir = strings.TrimPrefix(entry, "CLAUDE_CONFIG_DIR=")
		}
	}
	if count != 1 || configDir != "/home/dev/projects/genixis/.claude-legs/ai-issue-607/config" {
		t.Errorf(
			"harnessEnv set %d entries for CLAUDE_CONFIG_DIR, last %q; want one entry with the leg directory",
			count,
			configDir,
		)
	}
	if !slices.Contains(env, "HOME=/home/dev") {
		t.Errorf("harnessEnv dropped the environment of the caller: %q", env)
	}
}

// A caller that names no instance keeps its whole environment; the empty
// config directory never reaches the variable.
func TestHarnessEnvKeepsTheCallerShape(t *testing.T) {
	before := os.Environ()
	t.Setenv("CLAUDE_CONFIG_DIR", "")
	count := 0
	for _, entry := range harnessEnv("/anywhere/config") {
		if strings.HasPrefix(entry, "CLAUDE_CONFIG_DIR=") {
			count++
		}
	}
	if count != 1 {
		t.Errorf("harnessEnv wrote %d entries for CLAUDE_CONFIG_DIR, want one", count)
	}
	if len(before) == 0 {
		t.Errorf("the environment of the caller held no entry to keep")
	}
}
