package main

import (
	"testing"
)

// The tmux, WezTerm, and nvim panes of the builder stay outside these tests;
// the scratch acceptance of issue #74 covers them. This file pins the pure
// decisions of the builder that survive without them.

// The ending of the detach path: how a finished session reaches its person.
// The remote half of a delegated open or spawn prints no attach hint, and a
// direct run on the remote host keeps it (issue #136).
func TestDetachReaching(t *testing.T) {
	cases := []struct {
		name       string
		shown      bool
		wezterm    bool
		overSSH    bool
		remoteHalf bool
		want       detachReach
	}{
		{"a terminal shows the session", true, false, false, false, reachShown},
		{"a shown session wins over every other case", true, true, false, true, reachShown},
		{"a wezterm host outside ssh opens the tab", false, true, false, false, reachHostTab},
		{"over ssh the hint names the command", false, true, true, false, reachHint},
		{"without wezterm the hint names the command", false, false, false, false, reachHint},
		{"the remote half prints no hint over ssh", false, true, true, true, reachQuiet},
		{"the remote half prints no hint without wezterm", false, false, false, true, reachQuiet},
		{"the remote half prints no hint over ssh without wezterm", false, false, true, true, reachQuiet},
	}
	for _, tc := range cases {
		got := detachReaching(tc.shown, tc.wezterm, tc.overSSH, tc.remoteHalf)
		if got != tc.want {
			t.Errorf("%s: detachReaching = %v, want %v", tc.name, got, tc.want)
		}
	}
}
