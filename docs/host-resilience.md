# host-resilience

The four layers that keep a spawn storm on the host `services` from freezing the host.

Domain: what. Reader: a session that changes the memory, swap, or watchdog settings of a server, or the spawn gate of the project tool.
Code: modules/hardware/user-slice-memory.nix, modules/hardware/zram.nix, modules/hardware/watchdog.nix, modules/programs/cli/project/memorygate.go.

## What is the topic?

Four layers bound every spawn storm, ranked by how much future they survive (issue 267):

1. A kernel-enforced memory boundary on the slice of the dev user.
2. Zram, so memory pressure degrades instead of thrashing the page cache.
3. A watchdog that turns a remaining hang into an automatic reset.
4. A spawn gate in the project tool.

## How is the topic realized?

1. The memory boundary: the slice `user-1000` carries `MemoryHigh = 10G` and `MemoryMax = 12G` as a drop-in, and the module pins the uid of `dev` to 1000 with an assertion (user-slice-memory.nix:25-43). Every spawn path lands in the user slice, also paths that do not exist today, so this layer bounds every storm.
2. Zram: enabled at fifty percent of memory, an eight GiB device on the sixteen GiB host (zram.nix:8-14).
3. The watchdog: the softdog kernel module loads as the fallback, and `RuntimeWatchdogSec = 30s` makes PID 1 ping the device about every fifteen seconds. A hang resets the host within about thirty seconds (watchdog.nix:7-23). The reset takes the node cleanly offline, so the tailnet failover to `media` engages.
4. The spawn gate: `project spawn` and `project ide open` read the memory headroom of the host and refuse below two GiB, with exit code 12. The dispatcher retries the refusal twice (memorygate.go:9-40, 29-40; modules/services/dispatcher/README.md:127-130).

The dispatcher adds its own pacing: one leg per sweep pass and a minimum spacing of sixty seconds (docs/services.md).

## Why is the topic that way?

On 2026-11-09, thirteen session windows in ninety-five seconds filled the sixteen GiB host with anonymous pages. The host ran no swap, so the kernel could only reclaim page cache: every executable page faulted in, was evicted, and faulted again, and the host ran at about one percent speed for sixteen minutes until a power cut. Allocation always succeeded, so the OOM killer never ran. This is the no-swap livelock (issue 267).

The layers follow from it: the kernel boundary is first because it needs no cooperation; zram turns the pressure into degradation; the watchdog catches the rest; the tool gate is fourth because an agent can bypass the tool with raw tmux (issue 267).

Three refinements landed with the layers:

1. The slice cap covers the session scopes of ssh logins too, not only the user manager, because a tmux server that an ssh login starts lands in the session scope of that login (issue 271; user-slice-memory.nix).
2. The gate reads MemAvailable plus SwapFree, and it fails open on a host without /proc/meminfo, because it is a courtesy layer (memorygate.go:29-40).
3. The ide builder answers for an open window before the gate runs, so an open window stays reachable below the floor, because it is where a person stops a session (issue 273; cmd_ide.go:149).

## What does the topic enable?

The end of the topic: no spawner makes the host unusable. The failure stays inside the sessions of the dev user, the host answers or resets, and the LAN keeps its internet path through the failover. Issue 267 states the goal.

## How does a reader use and change the topic?

Change a limit: edit the module of the layer, and cite the measured basis. The numbers of the incident: sixteen GiB of memory, no disk swap, about three GiB of standing stack outside the slice, so the caps leave about one GiB of headroom when the cap binds (issue 267). Re-measure the standing stack after a rebuild with free and systemd-cgtop, and lower the caps when the stack grows past four GiB.

The owner verifies the layers after a rebuild of services (issue 267, acceptance):

1. The storm test: open thirteen session windows inside two minutes from an ssh login of dev, with project spawn and a five-second sleep between them. The host passes when ssh answers, one container answers on its port, and the subnet route stays up. Close the stress worktrees afterwards.
2. The hang test: freeze init.scope as root with a write of 1 to /sys/fs/cgroup/init.scope/cgroup.freeze. The root cgroup itself exposes no freeze file, so init.scope is the path that runs (issue 272). The command resets the host by design.
3. The failover test: during the hang, from a client off the LAN, reach one address of 10.0.0.0/24 through media, and after the reset reach it again with no manual step.

Open verifications, with no recorded outcome:

1. The hardware watchdog of the host `services` with wdctl. Softdog stays the fallback until it passes (watchdog.nix:19-21; issue 267).
2. The three owner tests above.
3. The re-measure of the standing stack.

The register of pending owner actions tracks them (issue 236).
