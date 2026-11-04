package main

import (
	"encoding/json"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

// This file is the WezTerm window layer (issue #101): one WezTerm window
// serves one host, and every tmux session of that host is one tab of it.
// Every path that puts a session on screen goes through weztermHostTab, the
// wezterm-attach command included. `ide pop` and the throwaway viewer
// sessions are the exception: they keep a window of their own through
// weztermOwnWindow.
//
// The window carries the host name as its pinned title, so tmux's set-titles
// cannot change it, and a tab carries its session name the same way. The
// pinned titles are the discovery state: the window is found by its title,
// and the tab of a session by its name, so at most one tab attaches to one
// session, because two tmux clients on one session mirror the current
// window of each other.

// weztermBase strips the tmux client environment from every wezterm call:
// `wezterm cli spawn` gives the environment of the caller to the new pane.
var weztermBase = []string{"-u", "TMUX", "-u", "TMUX_PANE", "wezterm"}

// weztermHomeTab is the tab title of the home tab of a host window. A
// project named home would share it; no project of this repository does.
const weztermHomeTab = "home"

// weztermPane is one entry of `wezterm cli list --format json`: one pane
// with the tab and the window it belongs to, and their pinned titles.
type weztermPane struct {
	PaneID      int    `json:"pane_id"`
	TabID       int    `json:"tab_id"`
	WindowID    int    `json:"window_id"`
	TabTitle    string `json:"tab_title"`
	WindowTitle string `json:"window_title"`
}

// weztermWindowWithTitle finds the host window by its pinned title: the
// first listed pane of a window with that title names the window id. A
// window without a pinned title never matches, and neither does the empty
// title.
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

// hostnameTitle is the window title of a host window: the host name without
// its domain, in lower case, so the discovery and the title write of every
// call agree whatever the resolver answers.
func hostnameTitle(host string) string {
	if at := strings.Index(host, "."); at >= 0 {
		host = host[:at]
	}
	return strings.ToLower(host)
}

// localHostTitle is the title of the window of this machine.
func localHostTitle() string {
	host, err := os.Hostname()
	if err != nil {
		return "localhost"
	}
	return hostnameTitle(host)
}

// weztermHomeTabArgs is the spawn command line of the home tab: a fish in
// ~/projects that prints the logo and the system information through
// fastfetch once at its start. -C runs one command after the config and the
// shell stays interactive, and no other pane prints any of it. The pane
// starts no login shell of its own, so it takes $SHELL of the GUI.
func weztermHomeTabArgs(cwd string) []string {
	args := []string{"--no-auto-start", "spawn", "--new-window"}
	if cwd != "" {
		args = append(args, "--cwd", cwd)
	}
	return append(args, "--", "sh", "-c", `exec "${SHELL:-fish}" -C fastfetch`)
}

// projectsDir is ~/projects, the working directory of the home tab.
func projectsDir() string {
	home, err := os.UserHomeDir()
	if err != nil {
		return ""
	}
	return filepath.Join(home, "projects")
}

// weztermAttach puts a local tmux session on screen as a tab of the window
// of this host: the tab runs a tmux attach on this machine.
func weztermAttach(target, name string, attached bool) (bool, error) {
	return weztermHostTab(localHostTitle(), name, []string{"tmux", "attach", "-t", target}, attached)
}

// weztermHostTab puts one tmux session on screen as a tab of the host window
// titled host: it finds the window by that title, it makes the window with
// its home tab when no window has the title, and it hands over to
// weztermSessionTab for the tab. attached reports that another client
// already shows the session; the return says whether a tab of the session is
// on screen. cmd is what the tab runs: a tmux attach, or an ssh to a remote
// session.
func weztermHostTab(host, name string, cmd []string, attached bool) (bool, error) {
	cli := append(append([]string{}, weztermBase...), "cli")
	windowID, ok := weztermWindowWithTitle(weztermList(cli), host)
	if !ok {
		if attached {
			return false, nil
		}
		pane, err := runEnvOutput(append(append([]string{}, cli...), weztermHomeTabArgs(projectsDir())...)...)
		if err != nil || pane == "" {
			// no running WezTerm answers: start one on the session itself.
			// A window of `wezterm start` cannot be titled from here, so the
			// host window appears with the next call that finds the GUI.
			weztermStart(cmd)
			return true, nil
		}
		homeTab, window := weztermPaneIDs(cli, pane)
		if window == 0 {
			return false, fmt.Errorf("wezterm: the home tab of the %s window never showed up", host)
		}
		// pin the titles, so the window stays the host window and the home
		// tab stays the home tab, whatever tmux or the panes push
		_ = runEnv(append(append(append([]string{}, cli...), "set-window-title", "--window-id", fmt.Sprint(window)), host)...)
		_ = runEnv(append(append(append([]string{}, cli...), "set-tab-title", "--tab-id", fmt.Sprint(homeTab)), weztermHomeTab)...)
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
	pane, err := runEnvOutput(append(append([]string{}, cli...), "--no-auto-start",
		"spawn", "--window-id", fmt.Sprint(windowID), "--"), cmd...)...)
	if err != nil || pane == "" {
		return false, fmt.Errorf("wezterm: no tab for session %s: %v", name, err)
	}
	// the tab title is pinned to the session name, so the next call finds
	// the tab and tmux cannot rename it. A list right after the spawn can
	// miss the fresh pane; the wait is bounded, and the titles of the next
	// call put a lost tab right.
	if tabID, _ := weztermPaneIDs(cli, pane); tabID != 0 {
		_ = runEnv(append(append(append([]string{}, cli...), "set-tab-title", "--tab-id", fmt.Sprint(tabID)), name)...)
		_ = runEnv(append(append(append([]string{}, cli...), "activate-tab", "--tab-id", fmt.Sprint(tabID))...)...)
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
	args := append(append([]string{"env"}, weztermBase...), "start", "--")
	detached("", append(args, cmd...)...)
}

// weztermOwnWindow opens one WezTerm window on a tmux session, outside the
// host grouping: `ide pop` and the throwaway viewer sessions keep a window
// of their own. The running GUI is asked first, and the new pane must not
// inherit the tmux client environment of the caller.
func weztermOwnWindow(session string) error {
	attach := append(append([]string{}, weztermBase...),
		"cli", "--no-auto-start", "spawn", "--new-window", "--", "tmux", "attach", "-t", session)
	cmd := exec.Command("env", attach...)
	cmd.Stdout = io.Discard
	cmd.Stderr = io.Discard
	if err := cmd.Run(); err == nil {
		return nil
	}
	weztermStart([]string{"tmux", "attach", "-t", session})
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
