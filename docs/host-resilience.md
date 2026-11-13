# host-resilience

Four layers that keep a spawn storm on the host `services` from freezing the host.

## Four Layers Against the Storm

Four layers bound every spawn storm, ranked by how much future they survive (issue 267):

1. A kernel-enforced memory boundary on the slice of the dev user.
2. Zram, so memory pressure degrades instead of thrashing the page cache.
3. A watchdog that turns a remaining hang into an automatic reset.
4. A spawn gate in the project tool.

## Four Layers, Ranked

1. Memory boundary: the slice `user-1000` carries `MemoryHigh = 10G` and `MemoryMax = 12G` as a drop-in, and the module pins the uid of `dev` to 1000 with an assertion (user-slice-memory.nix). Every spawn path lands in the user slice, also paths that do not exist today, so this layer bounds every storm.
2. Zram: enabled at fifty percent of memory, an eight GiB device on the sixteen GiB host (zram.nix).
3. Watchdog: the softdog kernel module loads as the fallback, and `RuntimeWatchdogSec = 30s` makes PID 1 ping the device about every fifteen seconds. A hang resets the host within about thirty seconds (watchdog.nix). A reset takes the node cleanly offline, so the tailnet failover to `media` engages.
4. Spawn gate: `project spawn` and `project ide open` read the memory headroom of the host and refuse below two GiB, with exit code 12. Dispatcher retries the refusal twice (memorygate.go; dispatcher/README.md).

Dispatcher adds its own pacing: one leg per sweep pass and a minimum spacing of sixty seconds (docs/services.md).

## No-Swap Livelock of 2026-11-09

On 2026-11-09, thirteen session windows in ninety-five seconds filled the sixteen GiB host with anonymous pages. That host ran no swap, so the kernel could only reclaim page cache: every executable page faulted in, was evicted, and faulted again, and the host ran at about one percent speed for sixteen minutes until a power cut. Allocation always succeeded, so the OOM killer never ran. This is the no-swap livelock (issue 267).

These layers follow from it: the kernel boundary is first because it needs no cooperation; zram turns the pressure into degradation; the watchdog catches the rest; the tool gate is fourth because an agent can bypass the tool with raw tmux (issue 267).

Three refinements landed with the layers:

1. Slice cap covers the session scopes of ssh logins too, not only the user manager, because a tmux server that an ssh login starts lands in the session scope of that login (issue 271; user-slice-memory.nix).
2. Gate reads MemAvailable plus SwapFree, and it fails open on a host without /proc/meminfo, because it is a courtesy layer (memorygate.go).
3. Ide builder answers for an open window before the gate runs, so an open window stays reachable below the floor, because it is where a person stops a session (issue 273; cmd_ide.go).

Deferred with a trigger: the microVM tier, only if Seatbelt or the proxy fail.

## Purpose of the Layers

Purpose of the topic: no spawner makes the host unusable. Failure stays inside the sessions of the dev user, the host answers or resets, and the LAN keeps its internet path through the failover. Issue 267 states the goal.

## Change and Verify the Layers

Change a limit: edit the module of the layer, and cite the measured basis. Numbers of the incident: sixteen GiB of memory, no disk swap, about three GiB of standing stack outside the slice, so the caps leave about one GiB of headroom when the cap binds (issue 267). Re-measure the standing stack after a rebuild with free and systemd-cgtop, and lower the caps when the stack grows past four GiB.

Owner verifies the layers after a rebuild of services (issue 267, acceptance):

1. Storm test: open thirteen session windows inside two minutes from an ssh login of dev, with project spawn and a five-second sleep between them. A host passes when ssh answers, one container answers on its port, and the subnet route stays up. Close the stress worktrees afterwards.
2. Hang test: freeze init.scope as root with a write of 1 to /sys/fs/cgroup/init.scope/cgroup.freeze. A root cgroup itself exposes no freeze file, so init.scope is the path that runs (issue 272). This command resets the host by design.
3. Failover test: during the hang, from a client off the LAN, reach one address of 10.0.0.0/24 through media, and after the reset reach it again with no manual step.

Open verifications, with no recorded outcome:

1. Hardware watchdog of the host `services` with wdctl. Softdog stays the fallback until it passes (watchdog.nix; issue 267).
2. Three owner tests above.
3. Re-measure of the standing stack.

Register of pending owner actions tracks them (issue 236).
