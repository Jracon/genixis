package main

import (
	"os"
	"path/filepath"
	"sync/atomic"
	"testing"
	"time"
)

// The watchdog of an ide window (issues #128 and #196): the loop coalesces,
// it ends with its pane and with its watcher, and the refresh vector is a
// contract with the nvim of the window and its tree module. The tmux and
// nvim panes stay outside these tests, the same way the builder panes do.

// The refresh command is a contract with two parties: nvim's --server mode
// reads the vector, and genixis.tree of neovim/lua/genixis reads the
// expression. The expression names the module and the function; the test
// pins both halves together.
func TestNvimRefreshArgsPinned(t *testing.T) {
	got := nvimRefreshArgs("/tmp/nvim-ide-96324-81.sock")
	want := []string{
		"nvim", "--headless", "--server", "/tmp/nvim-ide-96324-81.sock",
		"--remote-expr", `luaeval('require("genixis.tree").refresh()')`,
	}
	if len(got) != len(want) {
		t.Fatalf("refresh args = %v, want %v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Errorf("refresh args = %v, want %v", got, want)
		}
	}
	if treeRefreshExpr != `luaeval('require("genixis.tree").refresh()')` {
		t.Errorf("refresh expr = %q, want the genixis.tree refresh call", treeRefreshExpr)
	}
}

// One burst of git events coalesces into one refresh: every event restarts
// the quiet window, and only its end emits. A git switch that rewrites the
// metadata of the whole tree costs one emit, not one per file.
func TestWatchLoopCoalescesOneBurst(t *testing.T) {
	events := make(chan struct{})
	var emits atomic.Int32
	done := make(chan struct{})
	go func() {
		watchLoopTimed(events, func() bool { return true }, func() { emits.Add(1) }, time.Hour, 30*time.Millisecond)
		close(done)
	}()
	for i := 0; i < 200; i++ {
		events <- struct{}{}
		time.Sleep(time.Millisecond)
	}
	time.Sleep(150 * time.Millisecond)
	if n := emits.Load(); n != 1 {
		t.Errorf("%d emits for one burst of 200 events, want 1", n)
	}
	close(events)
	select {
	case <-done:
	case <-time.After(time.Second):
		t.Fatal("the loop did not end with its watcher")
	}
}

// Two bursts that sit one quiet window apart give one emit each.
func TestWatchLoopEmitsOncePerBurst(t *testing.T) {
	events := make(chan struct{})
	var emits atomic.Int32
	done := make(chan struct{})
	go func() {
		watchLoopTimed(events, func() bool { return true }, func() { emits.Add(1) }, time.Hour, 20*time.Millisecond)
		close(done)
	}()
	defer close(events)
	events <- struct{}{}
	time.Sleep(100 * time.Millisecond)
	events <- struct{}{}
	time.Sleep(100 * time.Millisecond)
	if n := emits.Load(); n != 2 {
		t.Errorf("%d emits for two bursts, want 2", n)
	}
}

// The watchdog ends when its pane is gone, without a last emit.
func TestWatchLoopEndsWithItsPane(t *testing.T) {
	events := make(chan struct{})
	var emits atomic.Int32
	done := make(chan struct{})
	go func() {
		watchLoopTimed(events, func() bool { return false }, func() { emits.Add(1) }, 5*time.Millisecond, time.Hour)
		close(done)
	}()
	defer close(events)
	select {
	case <-done:
	case <-time.After(time.Second):
		t.Fatal("the loop did not end on a dead pane")
	}
	if n := emits.Load(); n != 0 {
		t.Errorf("%d emits before the end, want 0", n)
	}
}

// The platform watcher reports the churn that git makes in its directory: a
// lock file appears and is renamed over its target, the shape of every index
// and ref write.
func TestDirWatcherFiresOnGitChurn(t *testing.T) {
	dir := t.TempDir()
	w, err := newDirWatcher(dir)
	if err != nil {
		t.Fatal(err)
	}
	defer w.Close()
	lock := filepath.Join(dir, "index.lock")
	if err := os.WriteFile(lock, []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	expectEvent(t, w)
	if err := os.Rename(lock, filepath.Join(dir, "index")); err != nil {
		t.Fatal(err)
	}
	expectEvent(t, w)
}

// Close ends the watch: the channel closes and no event follows.
func TestDirWatcherCloseEndsTheWatch(t *testing.T) {
	dir := t.TempDir()
	w, err := newDirWatcher(dir)
	if err != nil {
		t.Fatal(err)
	}
	w.Close()
	select {
	case _, ok := <-w.Events():
		if ok {
			t.Fatal("an event arrived after Close")
		}
	case <-time.After(2 * time.Second):
		t.Fatal("Close did not end the watch")
	}
}

func expectEvent(t *testing.T, w *dirWatcher) {
	t.Helper()
	select {
	case <-w.Events():
	case <-time.After(2 * time.Second):
		t.Fatal("no event for the churn of the watched directory")
	}
}
