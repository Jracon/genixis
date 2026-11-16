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
in
{
  inherit mediaEnvironment;
}
