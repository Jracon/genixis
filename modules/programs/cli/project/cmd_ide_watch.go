package main

import (
	"fmt"
	"io"
	"os/exec"
	"time"

	"genixis/project/internal/spec"
)

// This file is the tree watchdog of an ide window (issues #128 and #196). The
// file tree of the nvim pane watches the directories that it shows, so rows
// and git marks stay current after writes, git restore, and git switch. A git
// command that changes the index alone (git add, git commit, git rm --cached,
// git restore --staged) writes no file there, and the index of a worktree
// sits in the git directory of the main checkout, so no event reaches the
// tree and the marks stay stale. The watchdog closes that gap: it watches the
// git directory of the checkout, and one quiet window after each burst it
// tells the nvim of the window to rescan the tree, which re-runs the git
// status of every row.

// treeRefreshExpr is the expression that makes the nvim of the window rescan
// its file tree. The module name is a contract with
// neovim/lua/genixis/tree.lua; the test pins it.
const treeRefreshExpr = `luaeval('require("genixis.tree").refresh()')`

// watchQuiet is the quiet window that coalesces one burst of git events: a
// git switch rewrites HEAD, the index, and the commit files within a few
// milliseconds, and the whole burst becomes one rescan.
const watchQuiet = 300 * time.Millisecond

// watchTick is the liveness interval: the watchdog asks tmux for its pane and
// ends when the pane is gone, whatever ended it (ide close, a killed window,
// a dead server). The process holds no other polling: the watch itself is
// event-driven.
const watchTick = 5 * time.Second

// dirWatcher reports any change in one directory as one signal on its
// channel: the watcher coalesces, it does not classify. Close ends the watch
// and closes the channel.
type dirWatcher struct {
	events chan struct{}
	close  func()
}

func (w *dirWatcher) Events() <-chan struct{} {
	return w.events
}

func (w *dirWatcher) Close() {
	w.close()
}

// cmdIdeWatch is the `project ide watch` verb, which the builder starts
// detached beside the window: pane is the editor pane, sock the --listen
// socket of its nvim, and gitDir the git directory of the checkout.
func cmdIdeWatch(argv []string, stdout, stderr io.Writer) spec.ExitCode {
	if helpFlag(argv) {
		printCommandDoc(stdout, "ide watch")
		return spec.Success
	}
	if len(argv) != 3 || argv[0] == "" || argv[1] == "" || argv[2] == "" {
		fmt.Fprintln(stderr, "usage: ide watch <editor-pane> <sock> <git-dir>")
		return spec.ArgError
	}
	pane, sock, gitDir := argv[0], argv[1], argv[2]
	watcher, err := newDirWatcher(gitDir)
	if err != nil {
		fmt.Fprintf(stderr, "ide watch: %v\n", err)
		return spec.GeneralError
	}
	defer watcher.Close()
	// a missing receiver is not an error: nvim can quit and come back on the
	// same socket (ide reload does that), and the rescan lands on the new one
	watchLoop(watcher.Events(), func() bool { return paneAlive(pane) }, func() {
		args := nvimRefreshArgs(sock)
		_ = exec.Command(args[0], args[1:]...).Run()
	})
	return spec.Success
}

// nvimRefreshArgs is the command that tells the nvim of one window to rescan
// its tree. The vector is a contract with nvim's --server mode; the test pins
// it.
func nvimRefreshArgs(sock string) []string {
	return []string{"nvim", "--headless", "--server", sock, "--remote-expr", treeRefreshExpr}
}

// watchLoop is the watchdog core: one rescan per burst of events, because
// every event restarts the quiet window, and an end when the pane is gone or
// the watcher ends.
func watchLoop(events <-chan struct{}, alive func() bool, emit func()) {
	watchLoopTimed(events, alive, emit, watchTick, watchQuiet)
}

// watchLoopTimed is watchLoop with its intervals as arguments, so the tests
// can drive it fast.
func watchLoopTimed(events <-chan struct{}, alive func() bool, emit func(), tick, quiet time.Duration) {
	ticker := time.NewTicker(tick)
	defer ticker.Stop()
	var burst <-chan time.Time
	for {
		select {
		case _, ok := <-events:
			if !ok {
				return
			}
			burst = time.After(quiet)
		case <-burst:
			burst = nil
			emit()
		case <-ticker.C:
			if !alive() {
				return
			}
		}
	}
}

// paneAlive reports whether the tmux pane still exists: tmux fails on a pane
// that is gone, and on a server that is gone with it.
func paneAlive(pane string) bool {
	return tmuxDisplay(pane, "#{pane_id}") != ""
}

// gitAbsoluteDir is the git directory of dir as an absolute path: the
// per-worktree directory of a worktree, and the shared git directory for the
// main checkout. Empty outside a repository, where no watchdog starts.
func gitAbsoluteDir(dir string) string {
	out, err := runCmd(dir, nil, "git", "rev-parse", "--absolute-git-dir")
	if err != nil {
		return ""
	}
	return out
}
