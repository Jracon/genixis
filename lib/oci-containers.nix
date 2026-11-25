# The shared shapes of the container service modules. No host lists this
# file, so expandModules never loads it as a module; the service files
# import it.
let
  # The id of the media containers: the PUID and PGID environment of the
  # images, the user argument of the containers that take one, and the owner
  # that the activation scripts give the service directories under /mnt. The
  # media host names no user with this id (the ruling of issue #375 on the
  # playlist scripts), so this number is the one place that decides it.
  mediaId = 1000;

  # The address of the forge container on the default bridge of Podman. The
  # container claims it with a static assignment, because the ssh publish of
  # the forge is a DNAT rule that rewrites the destination of a connect to
  # the container address, and the egress filter of a leg unit of the
  # sandbox tier reads the destination after that rewrite, so the allow list
  # of a leg must name this address for the push path of the factory loop
  # (modules/services/sandbox-tier.nix, issue 658, the owner probe of
  # 2026-11-25). The address sits at the top of the first /24 of the default
  # bridge, because netavark hands the dynamic addresses of that bridge out
  # from the bottom, so a dynamic container reaches it only after two
  # hundred and fifty starts before the forge.
  forgeContainerAddress = "10.88.0.254";

  # The environment that the media containers share: the id pair above and
  # the timezone of the host. The caller passes config.time.timeZone, so
  # common/base.nix stays the one place that decides the zone (docs/flake.md,
  # one place per decision).
  mediaEnvironment = timeZone: {
    PGID = toString mediaId;
    PUID = toString mediaId;
    TZ = timeZone;
  };

  # The user:group argument of the containers that take one, built from the
  # id above; the activation scripts chown with the same pair.
  mediaUser = "${toString mediaId}:${toString mediaId}";

  # The standing flags of a container healthcheck. The command differs per
  # image, and a service overrides a wait where its image needs a longer
  # one; the call site names the reason of its override.
  healthcheck =
    {
      cmd,
      interval ? "10s",
      retries ? "5",
      startPeriod ? "30s",
      timeout ? "5s",
    }:
    [
      "--health-cmd=${cmd}"
      "--health-interval=${interval}"
      "--health-retries=${retries}"
      "--health-start-period=${startPeriod}"
      "--health-timeout=${timeout}"
    ];

  # The activation line that creates one podman network of a service. The
  # --ignore flag keeps the line idempotent across rebuilds, and the caller
  # keeps the attribute name of docs/containers.md: create_<service>-network.
  networkCreate = podman: name: ''
    ${podman}/bin/podman network create ${name}-network --ignore
  '';

  # The timer of a daily oneshot service of a container group: it starts the
  # named service unit once a day and joins timers.target.
  dailyTimer = unit: {
    timerConfig = {
      OnCalendar = "daily";
      Unit = "${unit}.service";
    };
    wantedBy = [ "timers.target" ];
  };

  # One arr manager of the linuxserver images with its anime twin: the two
  # containers share their image and differ only in the config directory
  # and the published port. The anime twin publishes one port above the
  # main one (docs/containers.md, the group table).
  arrPair =
    {
      config,
      image,
      name,
      port,
    }:
    {
      networking.firewall.allowedTCPPorts = [
        port
        (port + 1)
      ];

      system.activationScripts."create_${name}_directories".text = ''
        mkdir -p /mnt/${name} /mnt/${name}-anime
      '';

      virtualisation.oci-containers.containers = {
        ${name} = {
          inherit image;

          hostname = name;
          pull = "newer";

          environment = mediaEnvironment config.time.timeZone;
          ports = [
            "${toString port}:${toString port}"
          ];
          volumes = [
            "/mnt/${name}:/config"
            "/mnt/media:/mnt/media"
          ];
        };

        "${name}-anime" = {
          inherit image;

          hostname = "${name}-anime";
          pull = "newer";

          environment = mediaEnvironment config.time.timeZone;
          ports = [
            "${toString (port + 1)}:${toString port}"
          ];
          volumes = [
            "/mnt/${name}-anime:/config"
            "/mnt/media:/mnt/media"
          ];
        };
      };
    };
in
{
  inherit
    arrPair
    dailyTimer
    forgeContainerAddress
    healthcheck
    mediaEnvironment
    mediaId
    mediaUser
    networkCreate
    ;
}
