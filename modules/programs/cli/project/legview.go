package main

import (
	"io"
	"os/exec"
	"strings"
)

// This file is the view window of a headless leg (issue #116): one window
// in the tmux session named after the project, on the host of the spawn,
// named after the branch, whose pane runs claude attach on the background
// session of the leg. The owner reaches it through the session of the
// project and watches the leg work.
//
// The window ends with the leg: the attach client exits when the session
// stops, and tmux closes the pane and the window with it. `claude attach`
// opens a stopped session by name only while its process runs, so a pane
// that outlived its session reports the cause and exits instead of waking
// the session again. The window also carries the worktree in @leg_dir, and
// `project close` removes the windows that hold it.
//
// The window is a view, not a need of the leg: every failure here warns on
// stderr and leaves the leg running, and the machine contract of the spawn
// holds its envelope, its exit codes, and its --settings bytes.

// legDirOption marks a view window with the worktree of its leg, the way
// @ide_dir marks an ide window. `project close` reads it.
const legDirOption = "@leg_dir"

// legViewWindow opens the view window of a headless leg. session is the
// background session name, "<project>: <branch>". The window goes into the
// tmux session of the project: the one that `project open` shows, which is
// made here when no terminal opened it yet.
func legViewWindow(stderr io.Writer, project, tree, branch, session string) {
	if !commandExists("tmux") {
		printfDiag(stderr, "no tmux here, so %s runs with no view window", session)
		return
	}
	if err := tmuxServerCheck(); err != nil {
		printfDiag(stderr, "%s, so %s runs with no view window", err.err.Message, session)
		return
	}
	// the pane must find claude without the PATH of the tmux server: the
	// server of a dispatcher host carries the environment of whatever
	// started it, so the window names the absolute path that this spawn
	// itself ran claude from
	claude, err := exec.LookPath("claude")
	if err != nil {
		printfDiag(stderr, "claude is not on PATH, so %s runs with no view window", session)
		return
	}
	command, ok := legViewCommand(claude, session)
	if !ok {
		printfDiag(stderr, "the name of %s has no safe pane quoting, so it runs with no view window", session)
		return
	}
	tmuxSession := sessionName(project)
	var window string
	if sessionExists(tmuxSession) {
		window, err = tmux(legViewNewWindowArgs(tmuxSession, branch, tree, command)...)
	} else {
		// the session of the project does not exist: make it with this
		// window as its only one, sized like this terminal (the 80x24
		// default when none answers, as in a dispatcher unit), so a later
		// attach does not scale the panes up from a too-small session
		args := legViewNewSessionArgs(tmuxSession, branch, tree, terminalSize("cols"), terminalSize("lines"), command)
		window, err = idePane(args...)
	}
	if err != nil || window == "" {
		printfDiag(stderr, "tmux opened no view window for %s in session %s: %v", session, tmuxSession, err)
		return
	}
	_, _ = tmux("set-option", "-w", "-t", window, legDirOption, tree)
	printfDiag(stderr, "view window %q in tmux session %q", branch, tmuxSession)
}

// legViewCommand builds the pane command of the view window: the absolute
// claude with the session name as one argument. tmux runs a window command
// through the default shell, so the name is single-quoted, which fish, sh,
// and bash all read as one literal word. A name or a path with a single
// quote or a backslash has no form that every shell reads the same way, so
// the caller warns and opens no window.
func legViewCommand(claude, session string) (string, bool) {
	if claude == "" || session == "" || strings.ContainsAny(claude+session, `'\\`) {
		return "", false
	}
	return claude + " attach '" + session + "'", true
}

// legViewNewWindowArgs adds the view window to the tmux session of the
// project when that session exists. -P prints the window id for the option
// write, and =session: appends the window to that one session.
func legViewNewWindowArgs(session, name, dir, command string) []string {
	return []string{
		"new-window", "-d", "-P", "-F", "#{window_id}",
		"-t", "=" + session + ":", "-n", name, "-c", dir, command,
	}
}

// legViewNewSessionArgs makes the tmux session of the project with the view
// window as its only window: the session that `project open` and a
// delegated attach reach later. cols and lines size it like the terminal of
// the caller.
func legViewNewSessionArgs(session, name, dir, cols, lines, command string) []string {
	return []string{
		"new-session", "-d", "-P", "-F", "#{window_id}",
		"-s", session, "-n", name, "-c", dir,
		"-x", cols, "-y", lines, command,
	}
}
