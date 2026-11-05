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

// The command of a session tab of a remote login attaches to the session
// and then ends in an interactive login shell on that login, marked
// PROJECT_HOME_TAB the way the home tab is (issue #134), so a detach leaves
// the tab open on a shell prompt and the init of fish starts no second
// attach. The line is pinned word for word, because the login shell of the
// remote, fish or a POSIX shell alike, parses it.
func TestRemoteSessionCommand(t *testing.T) {
	want := `exec $SHELL -lc 'tmux attach -t =genixis; exec env PROJECT_HOME_TAB=1 "$SHELL" -l'`
	if got := remoteSessionCommand("genixis"); got != want {
		t.Errorf("remote session command = %q, want %q", got, want)
	}
}
