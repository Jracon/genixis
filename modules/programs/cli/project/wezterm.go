package main

import (
	"encoding/json"
	"fmt"
	"io"
	"os"
	"os/exec"
	"os/user"
	"path/filepath"
	"strings"
	"time"
)

// This file is the WezTerm window layer (issue #101): one WezTerm window
// serves one user on one host, and every tmux session of that user on that
// host is one tab of it. Every path that puts a session on screen goes
// through weztermHostTab, the wezterm-attach command included. `ide pop` and
// the throwaway viewer sessions are the exception: they keep a window of
// their own through weztermOwnWindow.
//
// The window carries user@host as its title, and a tab carries its session
// name the same way. A pane title replaces a title that a command pins, so
// the format-window-title event of the WezTerm config computes the window
// title (issue #115): the home tab of the window holds the marker, and the
// event returns the marker and writes it back, so the panes cannot keep
// their own titles there and `wezterm cli list` keeps reporting it. The
// titles are the discovery state: the window is found by its title, and the
// tab of a session by its name, so at most one tab attaches to one session,
// because two tmux clients on one session mirror the current window of each
// other. The user part keeps the sessions of two users on one host apart:
// their tmux servers are apart, and their session names can be equal.

// weztermBase strips the tmux client environment from every wezterm call:
// `wezterm cli spawn` gives the environment of the caller to the new pane.
var weztermBase = []string{"-u", "TMUX", "-u", "TMUX_PANE", "wezterm"}

// weztermHomeTab is the tab title of the home tab of the host window of
// this machine. A project named home would share it; no project of this
// repository does.
const weztermHomeTab = "home"

// homeTabTitle is the pinned tab title of the home tab of the window of one
// user and host: home on this machine, or the user@host of the login of a
// delegated window. The format-window-title event of the WezTerm config
// reads that title as the marker of the window and returns it as the window
// title (issue #115), so a delegated window keeps the title of its own
// login. The tab bar shows the working directory of the shell instead of
// the marker (issue #135): the format-tab-title event computes the display
// from the pane title, and the pinned marker stays beneath it.
func homeTabTitle(title string) string {
	if title == localWindowTitle() {
		return weztermHomeTab
	}
	return title
}

// weztermPane is one entry of `wezterm cli list --format json`: one pane
// with the tab and the window it belongs to, and their pinned titles.
type weztermPane struct {
	PaneID      int    `json:"pane_id"`
	TabID       int    `json:"tab_id"`
	WindowID    int    `json:"window_id"`
	TabTitle    string `json:"tab_title"`
	WindowTitle string `json:"window_title"`
}

// weztermWindowWithTitle finds a window by its pinned title: the first
// listed pane of a window with that title names the window id. A window
// without a pinned title never matches, and neither does the empty title.
func weztermWindowWithTitle(panes []weztermPane, title string) (int, bool) {
	if title == "" {
		return 0, false
	}
	for _, pane := range panes {
		if pane.WindowTitle == title {
			return pane.WindowID, true
		}
	}
	return 0, false
}

// weztermTabWithTitle finds the tab of a session in one window by its pinned
// title, so a second attach activates the open tab instead of adding a
// second client to the same tmux session.
func weztermTabWithTitle(panes []weztermPane, windowID int, title string) (int, bool) {
	for _, pane := range panes {
		if pane.WindowID == windowID && pane.TabTitle == title {
			return pane.TabID, true
		}
	}
	return 0, false
}

// hostnameTitle is the host part of a window title: the host name without
// its domain, in lower case, so the discovery and the title write of every
// call agree whatever the resolver answers.
func hostnameTitle(host string) string {
	if at := strings.Index(host, "."); at >= 0 {
		host = host[:at]
	}
	return strings.ToLower(host)
}

// hostWindowTitle is the title of the window of one user on one host:
// user@host, both parts in lower case and the host without its domain, so
// two calls agree however the prefix was typed and whatever the resolver
// answers.
func hostWindowTitle(user, host string) string {
	return strings.ToLower(user) + "@" + hostnameTitle(host)
}

// localWindowTitle is the title of the window of this user on this machine.
func localWindowTitle() string {
	host, err := os.Hostname()
	if err != nil {
		host = "localhost"
	}
	return hostWindowTitle(localUserName(), host)
}

// localUserName names the user of this process: the account entry first,
// then $USER of the environment, so a pane without the variable still gets
// the title of its user. The fallback keeps the title a valid form.
func localUserName() string {
	if current, err := user.Current(); err == nil && current.Username != "" {
		return current.Username
	}
	if name := os.Getenv("USER"); name != "" {
		return name
	}
	return "user"
}

// guiForward is the socket forward of one tab of a remote host window
// (issue #141): ssh -R listens on remote, a path unique to that connection,
// and connects through to local, the socket of the GUI that owns the
// window. The forward is a trust grant: through it, the account of the
// login on the remote host can drive the GUI of this machine and start
// processes on it (see "The host window" in AGENTS.md).
type guiForward struct {
	local  string
	remote string
}

// remoteSocketPath is the remote end of one forward: a path of the remote
// host, unique to the connection that holds it, so an ssh that dropped
// without its cleanup blocks no later connection. sshd of the remote host
// must allow stream local forwarding; the NixOS default does.
func remoteSocketPath() string {
	return fmt.Sprintf("/tmp/wezterm-fwd-%d-%d", os.Getpid(), time.Now().UnixNano())
}

// localGuiForward builds the forward that a new tab of a remote host window
// carries: a fresh remote path paired with the socket of the GUI on this
// machine. nil when no GUI socket answers, and then the tab carries no
// forward and a remote login keeps the behavior of a plain ssh. The local
// path is read again for every tab, because a restart of the GUI changes
// the pid in the name of its socket.
func localGuiForward() *guiForward {
	if local := guiSocketOnThisMachine(weztermSocketDir()); local != "" {
		return &guiForward{local: local, remote: remoteSocketPath()}
	}
	return nil
}

// carriedGuiForward builds the forward of a new tab from what this shell
// carries: PROJECT_GUI_SOCKET names the socket of the GUI on the machine
// that owns the window this shell sits in. nil when this shell holds no
// forward of a remote host window.
func carriedGuiForward() *guiForward {
	local := os.Getenv("PROJECT_GUI_SOCKET")
	if local == "" {
		return nil
	}
	return &guiForward{local: local, remote: remoteSocketPath()}
}

// guiForwarded reports whether this shell sits behind the socket forward
// of a window of a remote login: the ssh of its tab put the socket that
// WEZTERM_UNIX_SOCKET names on this host, and SSH_CONNECTION tells that
// this host is not the machine that owns the window. A pane of the GUI
// itself carries the variable too, but over no ssh, and its window opens
// a local tmux attach.
func guiForwarded() bool {
	return os.Getenv("SSH_CONNECTION") != "" && isSocket(os.Getenv("WEZTERM_UNIX_SOCKET"))
}

// forwardEnvArgs are the env assignments that carry a forward into the
// remote shell: WEZTERM_UNIX_SOCKET points wezterm cli of the remote host
// at the forwarded socket, and PROJECT_GUI_SOCKET names the socket on the
// machine that owns the window, so a tab that the remote half opens can
// carry a forward of its own. Empty when no forward exists.
func forwardEnvArgs(forward *guiForward) []string {
	if forward == nil {
		return nil
	}
	return []string{
		"WEZTERM_UNIX_SOCKET=" + forward.remote,
		"PROJECT_GUI_SOCKET=" + forward.local,
	}
}

// weztermSocketDir holds the sockets of the WezTerm GUI instances: the
// gui-sock-<pid> socket of the GUI sits in it. Upstream computes this one
// directory for its per-instance files (RUNTIME_DIR, config/src/lib.rs of
// wezterm; its troubleshooting page states the same place for the log
// files): the XDG runtime dir plus wezterm on Linux, and the
// .local/share/wezterm directory of the home directory on macOS and
// Windows. The issue names the same directory for m2pro-mbp. /tmp/wezterm
// answers a Linux session without the runtime dir; no host of this fleet
// runs one.
func weztermSocketDir() string {
	if !goosLinux {
		return filepath.Join(userHomeDir(), ".local", "share", "wezterm")
	}
	if dir := os.Getenv("XDG_RUNTIME_DIR"); dir != "" {
		return filepath.Join(dir, "wezterm")
	}
	return "/tmp/wezterm"
}

// guiSocketEntry is one socket of the socket dir with the time its file
// last changed.
type guiSocketEntry struct {
	name string
	mod  int64
}

// newestGuiSocket picks the socket of the running GUI from the entries of
// the socket dir: the newest one, because a GUI that died without its
// cleanup leaves its socket behind and the restart makes a fresh one.
// Empty when no entry exists.
func newestGuiSocket(entries []guiSocketEntry) string {
	newest := ""
	var newestMod int64
	for _, entry := range entries {
		if newest == "" || entry.mod > newestMod {
			newest, newestMod = entry.name, entry.mod
		}
	}
	return newest
}

// guiSocketOnThisMachine names the socket of the running WezTerm GUI: the
// variable of a pane while it points at a live socket, else the newest
// gui-sock of the socket dir. Empty when none answers.
func guiSocketOnThisMachine(socketDir string) string {
	if sock := os.Getenv("WEZTERM_UNIX_SOCKET"); isSocket(sock) {
		return sock
	}
	paths, err := filepath.Glob(filepath.Join(socketDir, "gui-sock-*"))
	if err != nil {
		return ""
	}
	var entries []guiSocketEntry
	for _, path := range paths {
		if info, statErr := os.Stat(path); statErr == nil && info.Mode()&os.ModeSocket != 0 {
			entries = append(entries, guiSocketEntry{name: path, mod: info.ModTime().UnixNano()})
		}
	}
	return newestGuiSocket(entries)
}

// remoteHomeCommand runs in the home tab of a remote login (issue #117):
// the remote login shell runs it, so $SHELL stays unquoted, or a fish
// remote reads it as the name of a command (delegationCommand keeps the
// same form). The login shell of the remote gives the full environment
// that finds fastfetch. The guard prints it when the remote build installs
// it; a remote without it starts the login shell alone. Both paths end in
// an interactive shell on that login. env sets PROJECT_HOME_TAB before the
// first shell starts: the interactive init of fish runs no bare tmux under
// that mark (issue #134), so the fastfetch output stays and the tab joins
// no session, and a plain ssh login keeps its auto-attach. The forward of
// the tab, when one exists, rides the same env prefix (issue #141), so the
// shell of the home tab can open tabs in the window it lives in.
func remoteHomeCommand(forward *guiForward) string {
	args := append([]string{"env", "PROJECT_HOME_TAB=1"}, forwardEnvArgs(forward)...)
	args = append(args, "$SHELL", "-lc", `'command -v fastfetch >/dev/null 2>&1 && exec "$SHELL" -l -C fastfetch; exec "$SHELL" -l'`)
	return "exec " + strings.Join(args, " ")
}

// sshTabArgs builds the ssh command line of one tab of a remote host
// window: a terminal (-t), the connect limit, and the forward of the GUI
// socket when one exists. cmd is what the remote login shell runs.
func sshTabArgs(target, cmd string, forward *guiForward) []string {
	args := []string{"ssh", "-o", "ConnectTimeout=10"}
	if forward != nil {
		args = append(args, "-R", forward.remote+":"+forward.local)
	}
	return append(args, "-t", target, "--", cmd)
}

// loginTarget gives the ssh target of the login that a window title names,
// when the title is not this user on this host: the titles of this layer
// are user@host (hostWindowTitle), so the login the title names is the
// title itself. An empty title and a title without @ name no login.
func loginTarget(title string) (string, bool) {
	if title == "" || title == localWindowTitle() || !strings.Contains(title, "@") {
		return "", false
	}
	return title, true
}

// weztermHomeTabArgs is the spawn command line of the home tab of the
// window with the given title. The window of this user on this host runs a
// fish in the home directory of the user that prints the logo and the
// system information through fastfetch once at its start. -C runs one
// command after the config and the shell stays interactive, and no other
// pane prints any of it. The pane starts no login shell of its own, so it
// takes $SHELL of the GUI. The window of another login runs its home tab
// on that login (issue #117): an interactive ssh to the target of the
// title, and no local shell and no local directory reach the pane. The ssh
// of that tab carries the forward of the GUI socket (issue #141), so the
// shell of the home tab opens tabs in its own window.
func weztermHomeTabArgs(title, cwd string, forward *guiForward) []string {
	args := []string{"--no-auto-start", "spawn", "--new-window"}
	if target, ok := loginTarget(title); ok {
		ssh := append([]string{"--"}, sshTabArgs(target, remoteHomeCommand(forward), forward)...)
		return append(args, ssh...)
	}
	if cwd != "" {
		args = append(args, "--cwd", cwd)
	}
	return append(args, "--", "sh", "-c", `exec "${SHELL:-fish}" -C fastfetch`)
}

// userHomeDir is ~, the working directory of the home tab.
func userHomeDir() string {
	home, err := os.UserHomeDir()
	if err != nil {
		return ""
	}
	return home
}

// weztermAttach puts a tmux session on screen as a tab of the window of
// this user on this host. The tab runs a tmux attach on this machine, or
// an ssh back into this login when this shell sits behind the forward of a
// remote host window (issue #141): the GUI that shows the new tab runs on
// the machine at the other end of the forward, so the tab must reach the
// tmux server here over ssh.
func weztermAttach(target, name string, attached bool) (bool, error) {
	cmd := []string{"tmux", "attach", "-t", target}
	if guiForwarded() {
		cmd = remoteAttachCommand(localWindowTitle(), name, carriedGuiForward())
	}
	return weztermHostTab(localWindowTitle(), name, cmd, attached)
}

// weztermHostTab puts one tmux session on screen as a tab of the window with
// the given title, the user@host of the layer above: it finds the window by
// that title, it makes the window with its home tab when no window has the
// title, and it hands over to weztermSessionTab for the tab. attached
// reports that another client already shows the session; the return says
// whether a tab of the session is on screen. cmd is what the tab runs: a
// tmux attach, or an ssh to a remote session.
func weztermHostTab(title, name string, cmd []string, attached bool) (bool, error) {
	cli := append(append([]string{}, weztermBase...), "cli")
	windowID, ok := weztermWindowWithTitle(weztermList(cli), title)
	if !ok {
		if attached {
			return false, nil
		}
		pane, err := runEnvOutput(append(append([]string{}, cli...), weztermHomeTabArgs(title, userHomeDir(), localGuiForward())...)...)
		if err != nil || pane == "" {
			// no running WezTerm answers: start one on the session itself.
			// A window of `wezterm start` cannot be titled from here, so the
			// window of this user appears with the next call that finds the
			// GUI.
			weztermStart(cmd)
			return true, nil
		}
		homeTab, window := weztermPaneIDs(cli, pane)
		if window == 0 {
			return false, fmt.Errorf("wezterm: the home tab of the %s window never showed up", title)
		}
		// write the window title once and pin the home tab title: the home
		// tab holds the marker that the WezTerm config reads, and the
		// config event keeps the window title on it from here on, whatever
		// tmux or the panes push
		_ = runEnv(append(append(append([]string{}, cli...), "set-window-title", "--window-id", fmt.Sprint(window)), title)...)
		_ = runEnv(append(append(append([]string{}, cli...), "set-tab-title", "--tab-id", fmt.Sprint(homeTab)), homeTabTitle(title))...)
		windowID = window
	}
	return weztermSessionTab(cli, windowID, name, cmd, attached)
}

// weztermSessionTab activates the tab of a session in the host window, or
// adds one when none is open.
func weztermSessionTab(cli []string, windowID int, name string, cmd []string, attached bool) (bool, error) {
	if tabID, ok := weztermTabWithTitle(weztermList(cli), windowID, name); ok {
		return true, runEnv(append(append([]string{}, cli...), "activate-tab", "--tab-id", fmt.Sprint(tabID))...)
	}
	if attached {
		// another client already shows the session: a new tab would mirror
		// it, so none is made and the caller reports the session as not
		// shown here
		return false, nil
	}
	pane, err := runEnvOutput(append(append(append([]string{}, cli...),
		"--no-auto-start", "spawn", "--window-id", fmt.Sprint(windowID), "--"), cmd...)...)
	if err != nil || pane == "" {
		return false, fmt.Errorf("wezterm: no tab for session %s: %v", name, err)
	}
	// the tab title is pinned to the session name, so the next call finds
	// the tab and tmux cannot rename it. A list right after the spawn can
	// miss the fresh pane; the wait is bounded, and the titles of the next
	// call put a lost tab right.
	if tabID, _ := weztermPaneIDs(cli, pane); tabID != 0 {
		_ = runEnv(append(append(append([]string{}, cli...), "set-tab-title", "--tab-id", fmt.Sprint(tabID)), name)...)
		_ = runEnv(append(append([]string{}, cli...), "activate-tab", "--tab-id", fmt.Sprint(tabID))...)
	}
	return true, nil
}

// weztermPaneIDs maps a spawned pane to its tab and window. A list right
// after the spawn can miss the new tab, so the mapping waits for the pane to
// appear; both stay 0 when it never does.
func weztermPaneIDs(cli []string, pane string) (tabID, windowID int) {
	for i := 0; i < 20; i++ {
		for _, entry := range weztermList(cli) {
			if fmt.Sprint(entry.PaneID) == pane {
				return entry.TabID, entry.WindowID
			}
		}
		time.Sleep(100 * time.Millisecond)
	}
	return 0, 0
}

// weztermStart starts the WezTerm GUI on one command, detached. `wezterm
// start` in a tmux pane starts a second GUI process apart from the Dock app,
// so only this fallback runs it, and it swallows its own failures the way
// the fish function did.
func weztermStart(cmd []string) {
	args := append(append(append([]string{}, weztermBase...), "start", "--"), cmd...)
	detached("", "env", args...)
}

// weztermOwnWindow opens one WezTerm window on a tmux session, outside the
// host grouping: `ide pop` and the throwaway viewer sessions keep a window
// of their own. The running GUI is asked first, and the new pane must not
// inherit the tmux client environment of the caller. The window attaches
// to the tmux server of this machine: over ssh when this shell sits behind
// the forward of a window of a remote login (issue #141), because the GUI
// runs on the machine at the other end of the forward.
func weztermOwnWindow(session string) error {
	cmd := []string{"tmux", "attach", "-t", session}
	if guiForwarded() {
		cmd = remoteAttachCommand(localWindowTitle(), session, carriedGuiForward())
	}
	spawn := append(append([]string{}, weztermBase...),
		"cli", "--no-auto-start", "spawn", "--new-window", "--")
	spawn = append(spawn, cmd...)
	run := exec.Command("env", spawn...)
	run.Stdout = io.Discard
	run.Stderr = io.Discard
	if err := run.Run(); err == nil {
		return nil
	}
	weztermStart(cmd)
	return nil
}

// weztermList reads the panes of the running GUI, empty when none answers.
func weztermList(cli []string) []weztermPane {
	out, err := runEnvOutput(append(append([]string{}, cli...), "list", "--format", "json")...)
	if err != nil || out == "" {
		return nil
	}
	var panes []weztermPane
	if err := json.Unmarshal([]byte(out), &panes); err != nil {
		return nil
	}
	return panes
}

// runEnv runs `env <kv...> <command...>` and waits for it.
func runEnv(args ...string) error {
	cmd := exec.Command("env", args...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}

// runEnvOutput runs `env <kv...> <command...>` and captures stdout.
func runEnvOutput(args ...string) (string, error) {
	cmd := exec.Command("env", args...)
	out, err := cmd.Output()
	return strings.TrimSpace(string(out)), err
}
