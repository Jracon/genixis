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
  image = "lscr.io/linuxserver/bazarr:latest";
  name = "bazarr";
  port = 6767;
}
