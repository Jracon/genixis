# The kernel-enforced memory boundary of the dev user (issue 267): a spawn
# storm filled the 16 GB of `services` with anonymous pages, and without swap
# the kernel thrashed the page cache instead of killing, so the host crawled
# for hours. The boundary is the slice user-1000.slice: it holds
# user@1000.service and every session-<n>.scope of dev, so a drop-in on the
# slice bounds every spawn path. A first tmux that starts from an ssh login
# lands in the session scope of that login, not in the user manager, so a cap
# on user@1000.service alone leaves that path open (issue 271).
#
# Measured basis (issue 267, journal of the frozen boot): 16 GB of RAM, about
# 3 GB of standing stack outside the slice (kernel, system services, and the
# containers). MemoryHigh 10G starts reclaim under pressure. MemoryMax 12G
# kills inside the slice when the cap binds. 16 GB minus 12 GB leaves 4 GB
# for the standing stack, so 1 GB of headroom stays above it.
#
# The dispatcher units of dev run inside the same slice. A storm can kill
# them, and the host stays usable. That trade is the purpose of this cap.
{
  config,
  ...
}:

{
  # the cap names the slice by uid, so the uid must stay pinned
  users.users.dev.uid = 1000;

  assertions = [
    {
      assertion = config.users.users.dev.uid == 1000;
      message = "user-slice-memory.nix caps user-1000.slice, but dev is not uid 1000; set users.users.dev.uid = 1000 or move the cap to the uid of dev";
    }
  ];

  systemd.slices."user-1000" = {
    # a drop-in, so it augments the slice unit that systemd-logind creates at
    # runtime; no unit file of this name exists to replace
    overrideStrategy = "asDropin";

    sliceConfig = {
      MemoryHigh = "10G";
      MemoryMax = "12G";
    };
  };
}
