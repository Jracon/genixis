# The automatic reset of a hung host (issue 267): the spawn storm of
# 2026-11-09 left userspace alive at one percent speed, so no watchdog of
# userspace fired, the tailnet never saw the node go offline, and the LAN
# kept routing into the dead subnet route until a person cut the power.
#
# runtimeTime 30 makes PID 1 ping /dev/watchdog every 15 s. A hang that
# stops the pings resets the host within about 30 s, the node leaves the
# tailnet, and the subnet route 10.0.0.0/24 fails over to media, which
# advertises the same route (tailscale/server.nix).
#
# The issue asks for a hardware watchdog, verified with wdctl, with softdog
# as the fallback. The permission system denied wdctl to the worker leg of
# issue 267, so this module loads the fallback: the softdog kernel timer.
# The kernel of the incident stayed alive and answered ping, so a kernel
# timer would have fired where userspace could not. Verify with wdctl after
# the rebuild: when a hardware watchdog exists, remove boot.kernelModules
# and keep runtimeTime alone, because a hardware timer is the stronger bound.
{
  boot.kernelModules = [
    "softdog"
  ];

  systemd.watchdog.runtimeTime = "30s";
}
