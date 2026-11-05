package main

import (
	"net"
	"os"
	"path/filepath"
	"slices"
	"testing"
	"time"
)

// The windows of issue #101, one per user and host: the pure finders read
// what `wezterm cli list --format json` reports, a window is found by its
// computed title (issue #115), and the tab of a session by its pinned name.
// The WezTerm calls themselves stay outside the tests; the scratch
// acceptance covers them.

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

// The home tab of the window of one user and host carries the marker that
// the WezTerm config reads as the window title: the reserved home name on
// this machine, or the login of a delegated window.
func TestHomeTabTitle(t *testing.T) {
	if got := homeTabTitle(localWindowTitle()); got != "home" {
		t.Errorf("home tab title of the local window = %q; want home", got)
	}
	if got := homeTabTitle(delegatedTitle); got != delegatedTitle {
		t.Errorf("home tab title of a delegated window = %q; want %s", got, delegatedTitle)
	}
}

// delegatedTitle is the title of a delegated window that no machine holds
// as its local one: the tests of the remote home tab must take the remote
// branch on every machine, also on services as dev, where dev@services is
// the title of the local window.
const delegatedTitle = "root@alpha-tower"

// A window title names a remote login when it is not this user on this
// host, and the title itself is the ssh target of that login.
func TestLoginTarget(t *testing.T) {
	if target, ok := loginTarget(localWindowTitle()); ok {
		t.Errorf("the local window title named a remote login: %q", target)
	}
	if target, ok := loginTarget(""); ok {
		t.Errorf("the empty title named a remote login: %q", target)
	}
	if target, ok := loginTarget("services"); ok {
		t.Errorf("a title without a login user named a remote login: %q", target)
	}
	if target, ok := loginTarget(delegatedTitle); !ok || target != delegatedTitle {
		t.Errorf("login target of a delegated window = %q, %v; want %s, true", target, ok, delegatedTitle)
	}
}

// The home tab of a remote login stays a plain shell: the command marks
// its pane with PROJECT_HOME_TAB, and the interactive init of fish runs
// no bare tmux under that mark (issue #134), so the fastfetch output stays
// and the tab joins no session, and a plain ssh login keeps its
// auto-attach. The line is pinned word for word, because the login shell
// of the remote, fish or a POSIX shell alike, parses it. The forward of the
// tab rides the same env prefix (issue #141): the shell of the home tab
// opens tabs in the window it lives in.
func TestRemoteHomeCommand(t *testing.T) {
	want := `exec env PROJECT_HOME_TAB=1 $SHELL -lc 'command -v fastfetch >/dev/null 2>&1 && exec "$SHELL" -l -C fastfetch; exec "$SHELL" -l'`
	if got := remoteHomeCommand(nil); got != want {
		t.Errorf("remote home command = %q, want %q", got, want)
	}
	forward := &guiForward{local: "/tmp/gui-sock-4", remote: "/tmp/wezterm-fwd-7"}
	want = `exec env PROJECT_HOME_TAB=1 WEZTERM_UNIX_SOCKET=/tmp/wezterm-fwd-7 PROJECT_GUI_SOCKET=/tmp/gui-sock-4` +
		` $SHELL -lc 'command -v fastfetch >/dev/null 2>&1 && exec "$SHELL" -l -C fastfetch; exec "$SHELL" -l'`
	if got := remoteHomeCommand(forward); got != want {
		t.Errorf("remote home command with a forward = %q, want %q", got, want)
	}
}

// The home tab of a fresh host window: a fish in the home directory of
// the user that prints fastfetch once at its start, and nothing else in
// any other pane. The home tab of a remote login runs on that login: an
// ssh to the user and the host of the title, and no local shell and no
// local directory reach the pane. The ssh of the tab forwards the GUI
// socket when one exists (issue #141).
func TestHomeTabCommand(t *testing.T) {
	got := weztermHomeTabArgs(localWindowTitle(), "/home/dev", nil)
	want := []string{
		"--no-auto-start", "spawn", "--new-window",
		"--cwd", "/home/dev",
		"--", "sh", "-c", `exec "${SHELL:-fish}" -C fastfetch`,
	}
	if !slices.Equal(got, want) {
		t.Errorf("home tab command of the local window = %q, want %q", got, want)
	}
	// no home directory: the tab starts in the default one
	got = weztermHomeTabArgs(localWindowTitle(), "", nil)
	if slices.Contains(got, "--cwd") {
		t.Errorf("home tab command of no cwd keeps --cwd: %q", got)
	}
	// the home tab of a delegated window runs on its login: the ssh of the
	// title, the remote command, and no local cwd
	got = weztermHomeTabArgs(delegatedTitle, "/home/dev", nil)
	want = []string{
		"--no-auto-start", "spawn", "--new-window",
		"--", "ssh", "-o", "ConnectTimeout=10", "-t", delegatedTitle, "--", remoteHomeCommand(nil),
	}
	if !slices.Equal(got, want) {
		t.Errorf("home tab command of a delegated window = %q, want %q", got, want)
	}
	if slices.Contains(got, "--cwd") {
		t.Errorf("home tab command of a remote login keeps a local cwd: %q", got)
	}
	// a GUI that answers gives the ssh of the tab a forward: -R names the
	// remote socket and the GUI socket of this machine, and the remote
	// command exports both paths to the login
	forward := &guiForward{local: "/tmp/gui-sock-4", remote: "/tmp/wezterm-fwd-7"}
	got = weztermHomeTabArgs(delegatedTitle, "/home/dev", forward)
	want = []string{
		"--no-auto-start", "spawn", "--new-window",
		"--", "ssh", "-o", "ConnectTimeout=10", "-R", "/tmp/wezterm-fwd-7:/tmp/gui-sock-4",
		"-t", delegatedTitle, "--", remoteHomeCommand(forward),
	}
	if !slices.Equal(got, want) {
		t.Errorf("home tab command with a forward = %q, want %q", got, want)
	}
}

// The ssh of a tab of a remote host window: a terminal, the connect limit,
// and the forward of the GUI socket when one exists. Without a forward the
// line stays the form that every build of the tool has run (issue #141
// changed only the case with one).
func TestSshTabArgs(t *testing.T) {
	got := sshTabArgs("dev@services", "exec $SHELL -l", nil)
	want := []string{"ssh", "-o", "ConnectTimeout=10", "-t", "dev@services", "--", "exec $SHELL -l"}
	if !slices.Equal(got, want) {
		t.Errorf("ssh of a tab without a forward = %q, want %q", got, want)
	}
	got = sshTabArgs("dev@services", "exec $SHELL -l",
		&guiForward{local: "/tmp/gui-sock-4", remote: "/tmp/wezterm-fwd-7"})
	want = []string{
		"ssh", "-o", "ConnectTimeout=10", "-R", "/tmp/wezterm-fwd-7:/tmp/gui-sock-4",
		"-t", "dev@services", "--", "exec $SHELL -l",
	}
	if !slices.Equal(got, want) {
		t.Errorf("ssh of a tab with a forward = %q, want %q", got, want)
	}
}

// The socket of the GUI is found again for every tab, because a restart of
// the GUI changes the pid in the name: the variable of a pane wins while it
// names a live socket, and otherwise the newest gui-sock of the data dir
// does, because a GUI that died without its cleanup leaves its socket
// behind.
func TestGuiSocketOnThisMachine(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("WEZTERM_UNIX_SOCKET", "")
	if got := guiSocketOnThisMachine(dir); got != "" {
		t.Errorf("socket of an empty data dir = %q, want none", got)
	}
	stale, _ := net.Listen("unix", filepath.Join(dir, "gui-sock-10"))
	defer stale.Close()
	fresh, _ := net.Listen("unix", filepath.Join(dir, "gui-sock-20"))
	defer fresh.Close()
	freshPath := filepath.Join(dir, "gui-sock-20")
	old := time.Now().Add(-time.Hour)
	if err := os.Chtimes(freshPath, time.Now(), time.Now()); err != nil {
		t.Fatal(err)
	}
	if err := os.Chtimes(filepath.Join(dir, "gui-sock-10"), old, old); err != nil {
		t.Fatal(err)
	}
	if got := guiSocketOnThisMachine(dir); got != freshPath {
		t.Errorf("socket of the data dir = %q, want the newest %q", got, freshPath)
	}
	// the variable of a pane wins while it names a live socket
	t.Setenv("WEZTERM_UNIX_SOCKET", stale.Addr().String())
	if got := guiSocketOnThisMachine(dir); got != stale.Addr().String() {
		t.Errorf("socket of the pane variable = %q, want %q", got, stale.Addr().String())
	}
	// a dead path in the variable falls back to the data dir
	t.Setenv("WEZTERM_UNIX_SOCKET", filepath.Join(dir, "gui-sock-gone"))
	if got := guiSocketOnThisMachine(dir); got != freshPath {
		t.Errorf("socket behind a dead pane variable = %q, want %q", got, freshPath)
	}
}

// newestGuiSocket picks the entry that changed last; ties keep the first
// entry, and no entry picks none.
func TestNewestGuiSocket(t *testing.T) {
	if got := newestGuiSocket(nil); got != "" {
		t.Errorf("newest of no entry = %q, want none", got)
	}
	entries := []guiSocketEntry{
		{name: "old", mod: 2},
		{name: "first", mod: 5},
		{name: "second", mod: 5},
	}
	if got := newestGuiSocket(entries); got != "first" {
		t.Errorf("newest of a tie = %q, want the first entry", got)
	}
}

// A shell behind the forward of a remote host window knows the GUI socket
// of the machine that owns the window from PROJECT_GUI_SOCKET, and a shell
// without a forward builds none.
func TestCarriedGuiForward(t *testing.T) {
	t.Setenv("PROJECT_GUI_SOCKET", "")
	if got := carriedGuiForward(); got != nil {
		t.Errorf("forward of no variable = %v, want none", got)
	}
	t.Setenv("PROJECT_GUI_SOCKET", "/tmp/gui-sock-4")
	got := carriedGuiForward()
	if got == nil || got.local != "/tmp/gui-sock-4" {
		t.Fatalf("forward of the variable = %v, want local /tmp/gui-sock-4", got)
	}
	if got.remote == "" || got.remote == got.local {
		t.Errorf("remote path of the forward = %q, want a fresh unique path", got.remote)
	}
}

// guiForwarded names the shell of a tab whose ssh put a socket on this
// host: the login came over ssh, and the variable names a live socket, so
// a pane of the GUI itself and a login whose forward never came up both
// keep the behavior of a local shell.
func TestGuiForwarded(t *testing.T) {
	live, _ := net.Listen("unix", filepath.Join(t.TempDir(), "gui-sock-live"))
	defer live.Close()
	t.Setenv("SSH_CONNECTION", "")
	t.Setenv("WEZTERM_UNIX_SOCKET", live.Addr().String())
	if guiForwarded() {
		t.Errorf("a pane of the GUI itself sat behind a forward")
	}
	t.Setenv("SSH_CONNECTION", "10.0.0.4 4242 10.0.0.9 22")
	t.Setenv("WEZTERM_UNIX_SOCKET", "")
	if guiForwarded() {
		t.Errorf("a plain ssh login without the variable sat behind a forward")
	}
	t.Setenv("WEZTERM_UNIX_SOCKET", filepath.Join(t.TempDir(), "gui-sock-gone"))
	if guiForwarded() {
		t.Errorf("a login whose forward never came up sat behind a forward")
	}
	t.Setenv("WEZTERM_UNIX_SOCKET", live.Addr().String())
	if !guiForwarded() {
		t.Errorf("the shell of a tab with a live forward sat behind no forward")
	}
}
