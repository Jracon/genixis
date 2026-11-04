package main

import (
	"strings"
	"testing"
)

// The command of a delegation must export the payload variable: fish keeps
// a variable of set -g inside the shell, so the remote project would read
// no marker and take the paths of a hand-run command, and their attach has
// no terminal.
func TestDelegationCommandExportsPayload(t *testing.T) {
	cmd := delegationCommand("cHJvamVjdA==")
	if !strings.Contains(cmd, "set -gx PROJECT_REMOTE_ARGV ") {
		t.Errorf("delegation command does not export the payload variable: %s", cmd)
	}
	if !strings.Contains(cmd, "base64 -d") {
		t.Errorf("delegation command does not decode the payload: %s", cmd)
	}
}
