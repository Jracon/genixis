package main

import (
	"os"
	"strconv"
	"strings"
)

// This file is the memory gate (issue 267): the fourth layer of the fix for
// the spawn storm that froze `services` on 2026-11-09. A session window
// fills host memory with anonymous pages (node, nvim, LSP servers,
// devshells), and a host whose free memory is gone cannot evict those pages,
// so it thrashes its page cache instead: allocation still succeeds, the OOM
// killer never runs, and the host crawls for hours. Before spawn and ide
// open anything, they read the headroom of the host and refuse when too
// little of it is left.
//
// The three layers below this one live in the host configuration
// (modules/hardware/ of the genixis repository): the slice cap bounds every
// spawner, also one that ignores this gate, because an agent can open a
// window with raw tmux. The gate keeps the honest spawners out of trouble.

// headroomFloorKB is the least free memory that a spawn or an ide window
// leaves on the host: 2 GiB, room for one more session window plus the
// reclaim slack of the page cache. The storm of issue 267 opened 13 windows
// in 95 s before the host thrashed; below the floor the kernel reclaims
// page cache faster than the sessions allocate, and the host slides into
// the livelock.
const headroomFloorKB int64 = 2 << 20

// meminfoPath is the kernel file the gate reads. The tests point it at a
// fixture, so their outcome never depends on the memory of the test host.
var meminfoPath = "/proc/meminfo"

// memoryGate refuses the window or session that what names, when the host is
// short of memory. The headroom is MemAvailable plus SwapFree: the memory
// the kernel can hand out without swapping, plus the swap it can still fill,
// which is zram on the hosts of this fleet. The refusal is UNAVAILABLE
// (exit 12), which the dispatcher retries after 30 and 120 s: that retry
// schedule is the queue of the gate.
//
// The gate fails open. A host without /proc/meminfo (Darwin) or a meminfo
// without the two fields passes: the gate is a courtesy layer, and a tool
// that cannot read its host must not brick the spawns of that host.
func memoryGate(what string) *toolError {
	content, err := os.ReadFile(meminfoPath)
	if err != nil {
		return nil
	}
	fields := meminfoFields(string(content))
	available, hasAvailable := fields["MemAvailable"]
	swapFree, hasSwap := fields["SwapFree"]
	if !hasAvailable || !hasSwap {
		return nil
	}
	headroom := available + swapFree
	if headroom >= headroomFloorKB {
		return nil
	}
	return errUnavailable(
		"%s refuses: the host has %s of memory headroom (MemAvailable %s + free swap %s), below the %s floor; stop a session or wait for one to end, then retry",
		what, memKB(headroom), memKB(available), memKB(swapFree), memKB(headroomFloorKB))
}

// meminfoFields reads the "Key:  value kB" lines of /proc/meminfo. A line
// without a number, or with a number the kernel did not decorate with a
// unit, is skipped, and the fields it would have carried read as absent.
func meminfoFields(content string) map[string]int64 {
	fields := map[string]int64{}
	for _, line := range strings.Split(content, "\n") {
		parts := strings.SplitN(line, ":", 2)
		if len(parts) != 2 {
			continue
		}
		words := strings.Fields(parts[1])
		if len(words) != 2 || words[1] != "kB" {
			continue
		}
		value, err := strconv.ParseInt(words[0], 10, 64)
		if err != nil {
			continue
		}
		fields[parts[0]] = value
	}
	return fields
}

// memKB formats a kB value of /proc/meminfo as GiB with one decimal.
func memKB(kb int64) string {
	return strconv.FormatFloat(float64(kb)/(1<<20), 'f', 1, 64) + " GiB"
}
