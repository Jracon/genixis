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
// refuses before it touches tmux, and a window that already exists is
// selected without a build, so the reuse never reads the memory either. The
// scratch PATH holds no tmux, so a gate that passed would fail the test on
// the missing binary instead of opening a window.
func TestIdeRefusesWhenMemoryIsShort(t *testing.T) {
	s := newScratch(t)
	setMeminfo(t, 256<<10, 0) // 0.25 GiB headroom, below the floor

	code, _, stderr := s.run("ide", s.dir)
	if spec.ExitCode(code) != spec.Unavailable {
		t.Fatalf("ide exit = %d, want %d: %s", code, spec.Unavailable, stderr)
	}
	if !strings.Contains(stderr, "memory headroom") {
		t.Errorf("stderr names no reason: %q", stderr)
	}
}
