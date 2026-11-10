# The resilience of the services host

The four layers that keep a spawn storm from making `services` unusable (issue 267). `modules/hardware/` holds the first three, and the project tool holds the fourth.

## The incident

On 2026-11-09 a task opened 13 session windows in 95 s. The windows filled the 16 GB of RAM with anonymous pages: node, nvim, LSP servers, devshells. The host had no swap, so the kernel could only reclaim page cache. Every executable page faulted in from disk, was evicted, and faulted again. Allocation always succeeded, so the OOM killer never ran. Every service ran at about one percent speed, ssh timed out, and the console did not echo. tailscaled never left the tailnet, so the failover of the subnet route 10.0.0.0/24 to `media` did not engage. A person cut the power after 16 minutes. This failure shape is the no-swap livelock: the host crawls instead of dying, and nothing recovers it.

## The layers

| Layer | Where | What it does |
| --- | --- | --- |
| Memory cap | `modules/hardware/user-slice-memory.nix` | The kernel bounds the slice of the dev user. |
| zram | `modules/hardware/zram.nix` | Pressure degrades into compressed swap in RAM. |
| Watchdog | `modules/hardware/watchdog.nix` | A hang that stops the pings resets the host. |
| Spawn gate | `modules/programs/cli/project/memorygate.go` | The tool refuses to open sessions on a short host. |

### The memory cap

`user-1000.slice` carries `MemoryHigh 10G` and `MemoryMax 12G` as a drop-in, so the slice unit that systemd-logind creates at runtime stays in place. The slice holds `user@1000.service` and every `session-<n>.scope` of `dev`, so the cap bounds every spawn path, also a spawner that no one knows today: the user manager of `dev`, the dispatcher units inside it, and a tmux server that started from an ssh login, which lands in the session scope of that login (issue 271). `MemoryHigh` starts reclaim under pressure. `MemoryMax` kills inside the slice when the cap binds. The dispatcher units of `dev` run inside the same slice, so a storm can kill them. That trade is the purpose: sessions of `dev` may die, and the host stays usable. The module pins the uid of `dev` at 1000 and asserts it, because the cap names the slice by that uid.

### zram

`zramSwap` gives the host an 8 GB compressed swap device in RAM (`memoryPercent 50` of 16 GB). Cold anonymous pages compress into it instead of evicting the page cache. The kill at `MemoryMax` then stays a late and clean event, instead of a long thrash.

### The watchdog

`systemd.settings.Manager.RuntimeWatchdogSec = "30s"` makes PID 1 ping `/dev/watchdog` every 15 s. A hang that stops the pings resets the host within about 30 s. The reset takes the node offline, so the subnet route 10.0.0.0/24 fails over to `media`, which advertises the same route (`modules/services/tailscale/server.nix`).

The issue asks for a hardware watchdog, verified with `wdctl`, with `softdog` as the fallback. The permission system denied `wdctl` to the worker leg, so the module loads the fallback. The kernel of the incident stayed alive, so the softdog kernel timer fires where userspace cannot. Verify after the rebuild:

```fish
wdctl
```

When the output names a hardware watchdog, remove `boot.kernelModules` from `watchdog.nix` and keep `RuntimeWatchdogSec` alone. A hardware timer is the stronger bound, because it also recovers from a locked kernel.

### The spawn gate

Before `project spawn` and `project ide` open anything, they read the headroom of the host: `MemAvailable` plus `SwapFree` from `/proc/meminfo`. Below a floor of 2 GiB they refuse with exit code 12, and the refusal names the headroom, the floor, and what to do. The dispatcher retries exit code 12 after 30 and 120 s, so the retry schedule is the queue of the gate. A window that already exists is selected without a build, and `project add` opens nothing, so neither reads the memory. The gate fails open on a host without `/proc/meminfo`, because the gate is a courtesy layer. An agent can bypass it with raw tmux, so the memory cap is the boundary and this layer is the fourth.

## The measured basis

The numbers of issue 267, read from the journal of the frozen boot:

| Item | Value |
| --- | --- |
| RAM of the host | 16 GB |
| Disk swap | none |
| Standing stack outside the dev slice | about 3 GB |
| `MemoryHigh` of the slice | 10G |
| `MemoryMax` of the slice | 12G |
| Headroom above the standing stack, when the cap binds | 16 − 12 − 3 = 1 GB |
| Floor of the spawn gate | 2 GiB of headroom |

The standing stack is the kernel, the system services, and the containers of the host. The leg could not re-measure it live, because `free` and `systemd-cgtop` are not on the allowlist of a leg. Re-measure after the rebuild, as `dev`:

```fish
free -h
systemd-cgtop -m -n1 --depth=1
```

When the standing stack grows past 4 GB, lower the caps of `user-slice-memory.nix` with it.

## What the owner verifies

The acceptance criteria of issue 267 name three host tests. Run them after the rebuild of `services`.

1. The storm test. Open at least 13 session windows within 2 minutes:

   ```fish
   for i in (seq 13)
       project spawn genixis stress-$i --permission-mode acceptEdits "Close this session at once."
       sleep 5
   end
   ```

   Run the loop from an ssh login of `dev`. The first tmux server of the host then starts in the session scope of that login. That path sat outside the first version of the cap, which covered the user manager only (issue 271). The cap on the slice bounds the session scopes too. The host passes when ssh answers, one container answers on its port, and the subnet route 10.0.0.0/24 stays up. Sessions of `dev` may die during the test. Remove the stress worktrees afterwards:

   ```fish
   for i in (seq 13)
       project close ~/projects/genixis/stress-$i
   end
   ```

2. The hang test. Freeze `init.scope` as root, from an ssh login outside the scope. The scope holds PID 1, so the freeze stops the watchdog pings, and the watchdog must reset the host within about one minute, with no person at the machine:

   ```fish
   echo 1 > /sys/fs/cgroup/init.scope/cgroup.freeze
   ```

   The root cgroup exposes no `cgroup.freeze` file, verified on `services`, so the freeze of `init.scope` is the path that runs (issue 272). The freeze holds PID 1, while the kernel and the ssh shell stay alive. This is the shape of the incident. The command resets the host by design, so run it in a window where a reboot costs nothing.

3. The failover test. During the hang test, from a client off the LAN, reach one address of 10.0.0.0/24 through `media`. After the reset, the address must answer again with no manual step. `tailscale status` names the node that carries the subnet route.
