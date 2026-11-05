package main

import (
	"crypto/rand"
	"encoding/binary"
	"fmt"
	"io"
	"os/exec"
	"strconv"
	"time"

	"genixis/project/internal/spec"
)

// This file is the yazi watchdog of an ide window (issue #128). Yazi watches
// the directory that its tab shows, so rows and git signs follow every file
// event in the worktree by themselves. A git command that changes the index
// alone (git add, git commit, git rm --cached, git restore --staged) writes
// no file there, and the index of a worktree sits in the git directory of the
// main checkout, so no event reaches yazi and the signs stay stale. The
// watchdog closes that gap: it watches the git directory of the checkout,
// and one quiet window after each burst it tells the yazi instance of the
// window to refresh its current tab, which re-runs the fetchers of the git
// plugin.

// yaziRefreshAction is the action that reloads the rows of the current tab
// and re-runs its fetchers, which is what moves the git signs. The keymap
// documentation of yazi 26.9.1 does not list it; the live pane of issue #128
// verified it, and the test below pins the name.
const yaziRefreshAction = "refresh"

// watchQuiet is the quiet window that coalesces one burst of git events: a
// git switch rewrites HEAD, the index, and the commit files within a few
// milliseconds, and the whole burst becomes one refresh.
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
// detached beside the window: pane is the yazi pane, client the DDS client id
// that yazi runs under, and gitDir the git directory of the checkout.
func cmdIdeWatch(argv []string, stdout, stderr io.Writer) spec.ExitCode {
	if len(argv) != 3 || argv[0] == "" || argv[1] == "" || argv[2] == "" {
		fmt.Fprintln(stderr, "usage: ide watch <pane> <client-id> <git-dir>")
		return spec.ArgError
	}
	pane, client, gitDir := argv[0], argv[1], argv[2]
	watcher, err := newDirWatcher(gitDir)
	if err != nil {
		fmt.Fprintf(stderr, "ide watch: %v\n", err)
		return spec.GeneralError
	}
	defer watcher.Close()
	// a missing receiver is not an error: the pane can outlive yazi, and the
	// emit finds it again after ide reload restarted yazi under the same id
	watchLoop(watcher.Events(), func() bool { return paneAlive(pane) }, func() {
		args := yaziEmitArgs(client)
		_ = exec.Command(args[0], args[1:]...).Run()
	})
	return spec.Success
}

// watchLoop is the watchdog core: one emit per burst of events, because every
// event restarts the quiet window, and an end when the pane is gone or the
// watcher ends.
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

// yaziEmitArgs is the command that tells the yazi instance of one window to
// refresh its current tab. The vector is a contract with the installed yazi;
// the test pins it.
func yaziEmitArgs(client string) []string {
	return []string{"ya", "emit-to", client, yaziRefreshAction}
}

// yaziStartCommand is the line that the builder types into the yazi pane: the
// y wrapper with the DDS client id that the watchdog emits to, or plain y
// outside a repository.
func yaziStartCommand(client string) string {
	if client == "" {
		return "y"
	}
	return "y --client-id " + client
}

// newYaziClientID picks the DDS client id of the yazi pane of one window: a
// random 9-digit number, unique among the few yazi instances of one user. An
// id that cannot be picked gives no watchdog, and the window keeps the
// behaviour it had before issue #128.
func newYaziClientID() string {
	var raw [4]byte
	if _, err := rand.Read(raw[:]); err != nil {
		return ""
	}
	return strconv.Itoa(int(binary.BigEndian.Uint32(raw[:])%900_000_000 + 100_000_000))
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
