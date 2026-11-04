package main

import (
	"slices"
	"testing"
)

// The windows of issue #101, one per user and host: the pure finders read
// what `wezterm cli list --format json` reports, a window is found by its
// pinned title, and the tab of a session by its pinned name. The WezTerm
// calls themselves stay outside the tests; the scratch acceptance covers
// them.

// hostWindowList is a desktop of two windows: the local one with a home tab
// and a session tab, the window of a remote user and host beside it, and a
// window without a pinned title that is no window of the layer at all.
func hostWindowList() []weztermPane {
	return []weztermPane{
		{PaneID: 0, TabID: 0, WindowID: 0},
		{PaneID: 1, TabID: 1, WindowID: 1, TabTitle: "home", WindowTitle: "jademeskill@m2pro-mbp"},
		{PaneID: 2, TabID: 2, WindowID: 1, TabTitle: "genixis", WindowTitle: "jademeskill@m2pro-mbp"},
		{PaneID: 3, TabID: 3, WindowID: 2, TabTitle: "home", WindowTitle: "dev@services"},
		{PaneID: 4, TabID: 4, WindowID: 2, TabTitle: "genixis", WindowTitle: "dev@services"},
	}
}

func TestWeztermHostWindowDiscovery(t *testing.T) {
	panes := hostWindowList()
	if id, ok := weztermWindowWithTitle(panes, "jademeskill@m2pro-mbp"); !ok || id != 1 {
		t.Errorf("window of the local user and host = %d, %v; want 1, true", id, ok)
	}
	if id, ok := weztermWindowWithTitle(panes, "dev@services"); !ok || id != 2 {
		t.Errorf("window of the remote user and host = %d, %v; want 2, true", id, ok)
	}
	// a second user on a host that already has a window gets none of it:
	// the sessions of two users never share one window
	if _, ok := weztermWindowWithTitle(panes, "root@services"); ok {
		t.Errorf("a window of another user was found")
	}
	if _, ok := weztermWindowWithTitle(panes, "services"); ok {
		t.Errorf("a window titled with the host alone was found")
	}
	// a window without a pinned title is no window of the layer, not even
	// for the empty title
	if _, ok := weztermWindowWithTitle(panes, ""); ok {
		t.Errorf("the empty title matched a window")
	}
}

func TestWeztermSessionTabByName(t *testing.T) {
	panes := hostWindowList()
	if id, ok := weztermTabWithTitle(panes, 1, "genixis"); !ok || id != 2 {
		t.Errorf("session tab = %d, %v; want 2, true", id, ok)
	}
	// the home tab is a tab of the same kind, under its reserved name
	if id, ok := weztermTabWithTitle(panes, 1, "home"); !ok || id != 1 {
		t.Errorf("home tab = %d, %v; want 1, true", id, ok)
	}
	if _, ok := weztermTabWithTitle(panes, 1, "themes"); ok {
		t.Errorf("a session with no tab was found")
	}
	// the tab of another window never matches, and neither does an untitled
	// tab
	if _, ok := weztermTabWithTitle(panes, 0, "home"); ok {
		t.Errorf("an untitled tab matched the home tab name")
	}
}

func TestHostnameTitle(t *testing.T) {
	for host, want := range map[string]string{
		"m2pro-mbp":            "m2pro-mbp",
		"m2pro-mbp.local":      "m2pro-mbp",
		"M2Pro-MBP.home":       "m2pro-mbp",
		"services.localdomain": "services",
		"desktop":              "desktop",
	} {
		if got := hostnameTitle(host); got != want {
			t.Errorf("hostnameTitle(%q) = %q, want %q", host, got, want)
		}
	}
}

// The title of a window is user@host, whatever the case of the parts and
// the domain of the resolver: two calls that name one login must agree.
func TestHostWindowTitle(t *testing.T) {
	for _, tc := range []struct{ user, host, want string }{
		{"jademeskill", "m2pro-mbp", "jademeskill@m2pro-mbp"},
		{"jademeskill", "m2pro-mbp.local", "jademeskill@m2pro-mbp"},
		{"dev", "services.localdomain", "dev@services"},
		{"Dev", "Services", "dev@services"},
	} {
		if got := hostWindowTitle(tc.user, tc.host); got != tc.want {
			t.Errorf("hostWindowTitle(%q, %q) = %q, want %q", tc.user, tc.host, got, tc.want)
		}
	}
}

// The home tab of a fresh host window: a fish in ~/projects that prints
// fastfetch once at its start, and nothing else in any other pane.
func TestHomeTabCommand(t *testing.T) {
	got := weztermHomeTabArgs("/home/dev/projects")
	want := []string{
		"--no-auto-start", "spawn", "--new-window",
		"--cwd", "/home/dev/projects",
		"--", "sh", "-c", `exec "${SHELL:-fish}" -C fastfetch`,
	}
	if !slices.Equal(got, want) {
		t.Errorf("home tab command = %q, want %q", got, want)
	}
	// no projects directory: the tab starts in the default one
	got = weztermHomeTabArgs("")
	if slices.Contains(got, "--cwd") {
		t.Errorf("home tab command of no cwd keeps --cwd: %q", got)
	}
}
