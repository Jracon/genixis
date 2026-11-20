{
  config,
  ...
}:

let
  # the shared shapes of the container modules (lib/oci-containers.nix)
  oci = import ../../../../lib/oci-containers.nix;
in
oci.arrPair {
  inherit config;
  image = "lscr.io/linuxserver/sonarr:latest";
  name = "sonarr";
  port = 8989;
}
