package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"time"
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

// The command of a session tab of a remote login re-sources the tmux
// configuration of the login before it attaches (issue #158: a server
// older than the last rebuild holds no new bindings), fails closed around
// the attach (issue #161: has-session gates it, and the tab prints a
// message that names the session instead of attaching against a host whose
// server is gone, because that attach starts a server and a first
// session), and then ends in an interactive login shell on that login,
// marked PROJECT_HOME_TAB the way the home tab is (issue #134), so a
// detach leaves the tab open on a shell prompt and the init of fish starts
// no second attach. The env of the forward rides the same line as its env
// prefix (issue #141). The line is pinned word for word, because the login
// shell of the remote, fish or a POSIX shell alike, parses it.
func TestRemoteSessionCommand(t *testing.T) {
	want := `exec $SHELL -lc 'tmux source-file -q ~/.config/tmux/tmux.conf >/dev/null 2>&1` +
		`; tmux has-session -t =genixis && tmux attach -t =genixis` +
		` || printf "tmux session genixis is gone\n"` +
		`; exec env PROJECT_HOME_TAB=1 "$SHELL" -l'`
	if got := remoteSessionCommand("genixis", nil); got != want {
		t.Errorf("remote session command = %q, want %q", got, want)
	}
	env := []string{"WEZTERM_UNIX_SOCKET=/tmp/wezterm-fwd-7", "PROJECT_GUI_SOCKET=/tmp/gui-sock-4"}
	want = `exec env WEZTERM_UNIX_SOCKET=/tmp/wezterm-fwd-7 PROJECT_GUI_SOCKET=/tmp/gui-sock-4` +
		` $SHELL -lc 'tmux source-file -q ~/.config/tmux/tmux.conf >/dev/null 2>&1` +
		`; tmux has-session -t =genixis && tmux attach -t =genixis` +
		` || printf "tmux session genixis is gone\n"` +
		`; exec env PROJECT_HOME_TAB=1 "$SHELL" -l'`
	if got := remoteSessionCommand("genixis", env); got != want {
		t.Errorf("remote session command with a forward = %q, want %q", got, want)
	}
}

// The guard of the session-tab command creates no tmux state itself
// (issue #161): a has-session against a socket without a server reports
// the missing session and leaves no server behind, because a server that
// holds no session ends at once, so the socket of the probe goes away. The
// probe runs the real tmux against its own socket, apart from the server
// of the login that runs the tests. It needs the tmux binary: the Nix
// check ships none, so it skips there and runs from a checkout that has
// one.
func TestTmuxHasSessionLeavesNoServer(t *testing.T) {
	if _, err := exec.LookPath("tmux"); err != nil {
		t.Skipf("tmux is not on PATH: %v", err)
	}
	socket := filepath.Join(t.TempDir(), "no-server")
	if err := exec.Command("tmux", "-S", socket, "has-session", "-t", "=no-such-session").Run(); err == nil {
		t.Fatalf("has-session of a missing session against no server succeeded")
	}
	for i := 0; i < 50; i++ {
		if _, err := os.Stat(socket); os.IsNotExist(err) {
			return // no socket: the probe left no server behind
		}
		time.Sleep(100 * time.Millisecond)
	}
	t.Errorf("has-session left a server behind on %s", socket)
}

// The tab command that puts a remote tmux session on screen runs on the
// machine that owns the window, so it ssh's into the login of the session
// (issue #141). Without a forward the ssh line stays the plain form that
// issue #141 does not change; with one, the ssh carries it and the command
// of the tab exports both socket paths.
func TestRemoteAttachCommand(t *testing.T) {
	got := remoteAttachCommand("dev@services", "genixis", nil)
	want := []string{
		"ssh", "-o", "ConnectTimeout=10", "-t", "dev@services", "--",
		"exec $SHELL -lc 'tmux source-file -q ~/.config/tmux/tmux.conf >/dev/null 2>&1; " +
			"tmux has-session -t =genixis && tmux attach -t =genixis" +
			" || printf \"tmux session genixis is gone\\n\"; " +
			"exec env PROJECT_HOME_TAB=1 \"$SHELL\" -l'",
	}
	if !slices.Equal(got, want) {
		t.Errorf("attach command without a forward = %q, want %q", got, want)
	}
	forward := &guiForward{local: "/tmp/gui-sock-4", remote: "/tmp/wezterm-fwd-7"}
	got = remoteAttachCommand("dev@services", "genixis", forward)
	want = []string{
		"ssh", "-o", "ConnectTimeout=10", "-R", "/tmp/wezterm-fwd-7:/tmp/gui-sock-4",
		"-t", "dev@services", "--",
		"exec env WEZTERM_UNIX_SOCKET=/tmp/wezterm-fwd-7 PROJECT_GUI_SOCKET=/tmp/gui-sock-4 " +
			"$SHELL -lc 'tmux source-file -q ~/.config/tmux/tmux.conf >/dev/null 2>&1; " +
			"tmux has-session -t =genixis && tmux attach -t =genixis" +
			" || printf \"tmux session genixis is gone\\n\"; " +
			"exec env PROJECT_HOME_TAB=1 \"$SHELL\" -l'",
	}
	if !slices.Equal(got, want) {
		t.Errorf("attach command with a forward = %q, want %q", got, want)
	}
}
