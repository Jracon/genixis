package main

import (
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"

	"genixis/project/internal/spec"
)

// The memory gate of issue 267: spawn and ide refuse to open anything when
// the host is short of memory, the refusal names the headroom and the floor,
// and it is UNAVAILABLE, the code the dispatcher retries. The gate reads
// /proc/meminfo through meminfoPath, and setMeminfo points that at a
// fixture, so no test outcome depends on the memory of the test host.

// setMeminfo writes one meminfo fixture with the given MemAvailable and
// SwapFree (in kB) and points the gate at it for the life of the test.
func setMeminfo(t *testing.T, memAvailableKB, swapFreeKB int64) {
	t.Helper()
	content := "MemTotal:       16384000 kB\n" +
		"MemFree:         1000000 kB\n" +
		"MemAvailable:   " + padKB(memAvailableKB) + " kB\n" +
		"HugePages_Total:       0\n" +
		"SwapTotal:       8388608 kB\n" +
		"SwapFree:       " + padKB(swapFreeKB) + " kB\n"
	path := filepath.Join(t.TempDir(), "meminfo")
	must(t, os.WriteFile(path, []byte(content), 0o644))
	old := meminfoPath
	meminfoPath = path
	t.Cleanup(func() { meminfoPath = old })
}

// padKB formats a kB value into the right-aligned field of a meminfo line.
func padKB(kb int64) string {
	field := strconv.FormatInt(kb, 10)
	return strings.Repeat(" ", 16-len(field)) + field
}

func TestMeminfoFieldsReadsTheKbLines(t *testing.T) {
	fields := meminfoFields("MemTotal:       16384 kB\n" +
		"MemAvailable:    1024 kB\n" +
		"HugePages_Total:       0\n" +
		"SwapFree: no number here\n" +
		"VmallocChunk:  34359738367\n")
	want := map[string]int64{
		"MemTotal":     16384,
		"MemAvailable": 1024,
	}
	if len(fields) != len(want) {
		t.Fatalf("fields = %v, want %v", fields, want)
	}
	for key, value := range want {
		if fields[key] != value {
			t.Errorf("fields[%s] = %d, want %d", key, fields[key], value)
		}
	}
}

// Below the floor the gate refuses with the code the dispatcher retries, and
// the refusal names the reason: the headroom of the host, the floor, and
// what to do.
func TestMemoryGateRefusesBelowTheFloor(t *testing.T) {
	setMeminfo(t, 512<<10, 256<<10) // 0.75 GiB headroom, below the 2 GiB floor
	err := memoryGate("spawn")
	if err == nil {
		t.Fatal("the gate passed below the floor")
	}
	if err.code != spec.Unavailable {
		t.Errorf("code = %d, want %d", err.code, spec.Unavailable)
	}
	for _, want := range []string{"memory headroom", "0.8 GiB", "2.0 GiB floor", "stop a session"} {
		if !strings.Contains(err.err.Message, want) {
			t.Errorf("refusal misses %q: %s", want, err.err.Message)
		}
	}
}

// MemAvailable and free swap add up: each alone is below the floor, the sum
// clears it.
func TestMemoryGateCountsSwapAsHeadroom(t *testing.T) {
	setMeminfo(t, 1<<20, 1<<20) // 1 GiB + 1 GiB = 2 GiB, at the floor passes
	if err := memoryGate("ide"); err != nil {
		t.Fatalf("the gate refused at the floor: %v", err)
	}
}

// The gate fails open: a host without /proc/meminfo (Darwin) or a meminfo
// without the two fields passes, because the gate is a courtesy layer, not a
// boundary.
func TestMemoryGateFailsOpen(t *testing.T) {
	old := meminfoPath
	meminfoPath = filepath.Join(t.TempDir(), "absent")
	t.Cleanup(func() { meminfoPath = old })
	if err := memoryGate("spawn"); err != nil {
		t.Fatalf("the gate refused without a meminfo: %v", err)
	}

	path := filepath.Join(t.TempDir(), "meminfo")
	must(t, os.WriteFile(path, []byte("MemTotal:       16384 kB\n"), 0o644))
	meminfoPath = path
	if err := memoryGate("spawn"); err != nil {
		t.Fatalf("the gate refused without the fields: %v", err)
	}
}

// A headless spawn under a short host refuses before any work happens: the
// envelope carries UNAVAILABLE, no worktree stays behind, and add — which
// opens nothing — still makes the claim. A --print-settings probe passes
// without a memory read, because it starts nothing.
func TestSpawnRefusesWhenMemoryIsShort(t *testing.T) {
	s := newScratch(t)
	setMeminfo(t, 512<<10, 256<<10)

	code, env, stderr := s.envelope("spawn", s.dir, "feat/x", "--headless", "--permission-mode", "dontAsk", "work")
	if spec.ExitCode(code) != spec.Unavailable {
		t.Fatalf("spawn exit = %d, want %d: %s", code, spec.Unavailable, stderr)
	}
	if errObj := env["error"].(map[string]any); errObj["code"] != "UNAVAILABLE" {
		t.Errorf("error = %v", errObj)
	}
	if !strings.Contains(stderr, "memory headroom") {
		t.Errorf("stderr names no reason: %q", stderr)
	}
	if _, err := os.Stat(filepath.Join(s.dir, "feat-x")); !os.IsNotExist(err) {
		t.Errorf("a refused spawn left a worktree behind")
	}

	// add opens nothing, so the claim happens under the same pressure
	code, _, stderr = s.envelope("add", s.dir, "feat/x")
	if spec.ExitCode(code) != spec.Success {
		t.Fatalf("add exit = %d: %s", code, stderr)
	}

	// the probe path starts nothing, so it never reads the memory
	code, stdout, stderr := s.run("spawn", s.dir, "feat/x", "--headless", "--print-settings", "x")
	if spec.ExitCode(code) != spec.Success {
		t.Fatalf("print-settings exit = %d: %s", code, stderr)
	}
	if !strings.Contains(stdout, "permissions") {
		t.Errorf("print-settings stdout = %q", stdout)
	}
}

// The ide builder carries the same gate: a build that would open a window
// refuses after its probes for an open window and before it opens a pane.
// The scratch PATH holds a tmux that fails every call, so no probe finds a
// session or a window, whatever server the test host runs. The -N probe of
// the Darwin server check is the one exception, as in fakeTmuxOpenWindow:
// the builder runs it before the gate, and a refusal there would end the
// run with the server error, not the memory refusal.
func TestIdeRefusesWhenMemoryIsShort(t *testing.T) {
	s := newScratch(t)
	s.fakeBin(t, "tmux", "#!/bin/sh\ncase \"$1\" in\n-N) exit 0 ;;\n*) exit 1 ;;\nesac\n")
	setMeminfo(t, 256<<10, 0) // 0.25 GiB headroom, below the floor

	code, _, stderr := s.run("ide", s.dir)
	if spec.ExitCode(code) != spec.Unavailable {
		t.Fatalf("ide exit = %d, want %d: %s", code, spec.Unavailable, stderr)
	}
	if !strings.Contains(stderr, "memory headroom") {
		t.Errorf("stderr names no reason: %q", stderr)
	}
}

// fakeTmuxOpenWindow puts a tmux script on the scratch PATH that answers the
// probes of one open ide window: the session exists, and the window @1 holds
// the directory. The -N probe of the Darwin server check also passes. Every
// call lands in a log file, so a test can prove which calls ran. Any call
// outside the probe set fails the script, so a path the test does not expect
// shows up as an error.
func (s *scratch) fakeTmuxOpenWindow(dir string) string {
	s.t.Helper()
	log := filepath.Join(s.t.TempDir(), "tmux.log")
	s.t.Setenv("FAKE_TMUX_LOG", log)
	script := "#!/bin/sh\n" +
		"echo \"$*\" >>\"$FAKE_TMUX_LOG\"\n" +
		"case \"$1\" in\n" +
		"-N) exit 0 ;;\n" +
		"has-session) exit 0 ;;\n" +
		"list-windows) printf '@1 %s\\n' " + strconv.Quote(dir) + " ;;\n" +
		"select-window) exit 0 ;;\n" +
		"attach) exit 0 ;;\n" +
		"*) echo \"unexpected tmux call: $*\" >&2 ; exit 1 ;;\n" +
		"esac\n"
	s.fakeBin(s.t, "tmux", script)
	return log
}

// readTmuxLog returns the calls that the fake tmux logged so far.
func readTmuxLog(t *testing.T, path string) string {
	t.Helper()
	raw, err := os.ReadFile(path)
	must(t, err)
	return string(raw)
}

// Below the floor, the selection of a window that is already open never
// passes the gate (issue 273): that window is where a person stops a
// session, also on a host without a GUI, where project open reaches it
// through the builder over ssh. The fake tmux answers the probes of one
// open window; the run selects it and opens no pane, outside tmux and
// inside it.
func TestIdeSelectsAnOpenWindowBelowTheMemoryFloor(t *testing.T) {
	s := newScratch(t)
	setMeminfo(t, 256<<10, 0) // 0.25 GiB headroom, below the floor
	log := s.fakeTmuxOpenWindow(s.dir)

	// outside tmux, the form project open takes over a plain ssh login: the
	// session exists and holds the window of this directory
	code, _, stderr := s.run("ide", s.dir)
	if spec.ExitCode(code) != spec.Success {
		t.Fatalf("ide exit = %d, want %d below the floor: %s", code, spec.Success, stderr)
	}
	calls := readTmuxLog(t, log)
	for _, want := range []string{"select-window -t @1", "attach -t =demo"} {
		if !strings.Contains(calls, want) {
			t.Errorf("tmux calls miss %q: %q", want, calls)
		}
	}
	for _, opened := range []string{"new-session", "new-window", "split-window"} {
		if strings.Contains(calls, opened) {
			t.Errorf("tmux calls hold %q, so the run opened something", opened)
		}
	}
	if strings.Contains(stderr, "headroom") {
		t.Errorf("the gate refused a selection: %q", stderr)
	}

	// inside tmux, the selection of the current session's window is one
	// select-window, with no attach
	must(t, os.WriteFile(log, nil, 0o644))
	t.Setenv("TMUX", "scratch,1,0")
	code, _, stderr = s.run("ide", s.dir)
	if spec.ExitCode(code) != spec.Success {
		t.Fatalf("ide inside tmux exit = %d: %s", code, stderr)
	}
	calls = readTmuxLog(t, log)
	if !strings.Contains(calls, "select-window -t @1") {
		t.Errorf("tmux calls inside tmux hold no selection: %q", calls)
	}
	if strings.Contains(calls, "new-window") {
		t.Errorf("the run inside tmux opened a window: %q", calls)
	}
}

// Below the floor, a --detach that finds a window of its directory names the
// window, not the memory (issue 273): the refusal of the builder's own rule
// comes before the gate, and the window does not go away when the host runs
// short.
func TestIdeDetachBelowTheFloorNamesTheOpenWindow(t *testing.T) {
	s := newScratch(t)
	setMeminfo(t, 256<<10, 0) // 0.25 GiB headroom, below the floor
	s.fakeTmuxOpenWindow(s.dir)

	code, _, stderr := s.run("ide", "--detach", "demo", s.dir)
	if spec.ExitCode(code) != spec.GeneralError {
		t.Fatalf("ide --detach exit = %d, want %d: %s", code, spec.GeneralError, stderr)
	}
	if !strings.Contains(stderr, "already has an ide window") {
		t.Errorf("stderr names no open window: %q", stderr)
	}
	if strings.Contains(stderr, "headroom") {
		t.Errorf("the gate answered for a window that exists: %q", stderr)
	}
}
