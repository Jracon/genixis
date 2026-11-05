package main

import (
	"slices"
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

// The tab command that puts a remote tmux session on screen runs on the
// machine that owns the window, so it ssh's into the login of the session
// (issue #141). Without a forward it keeps the form that every build of the
// tool has run; with one, the ssh carries it and the attach shell of the
// tab exports both socket paths.
func TestRemoteAttachCommand(t *testing.T) {
	got := remoteAttachCommand("dev@services", "genixis", nil)
	want := []string{
		"ssh", "-o", "ConnectTimeout=10", "-t", "dev@services", "--",
		"exec $SHELL -lc 'tmux attach -t =genixis'",
	}
	if !slices.Equal(got, want) {
		t.Errorf("attach command without a forward = %q, want %q", got, want)
	}
	forward := &guiForward{local: "/tmp/gui-sock-4", remote: "/tmp/wezterm-fwd-7"}
	got = remoteAttachCommand("dev@services", "genixis", forward)
	want = []string{
		"ssh", "-o", "ConnectTimeout=10", "-R", "/tmp/wezterm-fwd-7:/tmp/gui-sock-4",
		"-t", "dev@services", "--",
		"exec env WEZTERM_UNIX_SOCKET=/tmp/wezterm-fwd-7 PROJECT_GUI_SOCKET=/tmp/gui-sock-4 $SHELL -lc 'tmux attach -t =genixis'",
	}
	if !slices.Equal(got, want) {
		t.Errorf("attach command with a forward = %q, want %q", got, want)
	}
}
