package main

import (
	"os"
	"path/filepath"
	"sync/atomic"
	"testing"
	"time"
)

// The watchdog of an ide window (issue #128): the loop coalesces, it ends
// with its pane and with its watcher, and the emit vector is a contract with
// the installed yazi. The tmux and ya panes stay outside these tests, the
// same way the builder panes do; the live pane of the issue verified the
// vector end to end.

// The refresh action is a contract with the installed yazi: the keymap
// documentation of yazi 26.9.1 does not list it, and the live pane of issue
// #128 verified that it re-runs the fetchers of the current tab.
func TestYaziEmitArgsPinned(t *testing.T) {
	got, want := yaziEmitArgs("128128456"), []string{"ya", "emit-to", "128128456", "refresh"}
	if len(got) != len(want) {
		t.Fatalf("emit args = %v, want %v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Errorf("emit args = %v, want %v", got, want)
		}
	}
	if yaziRefreshAction != "refresh" {
		t.Errorf("refresh action = %q, want refresh", yaziRefreshAction)
	}
}

// The line the builder types into the yazi pane: the id is what makes the
// pane reachable from outside, and no id gives the plain wrapper.
func TestYaziStartCommand(t *testing.T) {
	for _, table := range []struct{ client, want string }{
		{"", "y"},
		{"128128456", "y --client-id 128128456"},
	} {
		if got := yaziStartCommand(table.client); got != table.want {
			t.Errorf("start command for %q = %q, want %q", table.client, got, table.want)
		}
	}
}

// The client id is a 9-digit number, so it cannot collide with the small ids
// of tmux panes, and two windows never share one.
func TestNewYaziClientID(t *testing.T) {
	first, second := newYaziClientID(), newYaziClientID()
	for _, id := range []string{first, second} {
		if !isDigits(id) || len(id) != 9 {
			t.Errorf("client id %q is not a 9-digit number", id)
		}
	}
	if first == second {
		t.Errorf("two client ids equal: %q", first)
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
