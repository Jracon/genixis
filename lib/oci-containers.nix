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
    mediaEnvironment
    mediaId
    mediaUser
    ;
}
