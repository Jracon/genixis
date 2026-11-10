# The kernel-enforced memory boundary of the dev user (issue 267): a spawn
# storm filled the 16 GB of `services` with anonymous pages, and without swap
# the kernel thrashed the page cache instead of killing, so the host crawled
# for hours. Every spawn path of a leg lands in user@1000.service, so a cap
# on that unit bounds every storm, also a spawner that no one knows today.
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
  assertions = [
    {
      assertion = config.users.users.dev.uid == null || config.users.users.dev.uid == 1000;
      message = "user-slice-memory.nix caps user@1000.service, but dev is not uid 1000; set users.users.dev.uid = 1000 or move the cap to the uid of dev";
    }
  ];

  systemd.services."user@1000" = {
    # a drop-in, so the generated unit does not replace the user@.service
    # template that systemd itself ships
    overrideStrategy = "asDropin";

    serviceConfig = {
      MemoryHigh = "10G";
      MemoryMax = "12G";
    };
  };
}
