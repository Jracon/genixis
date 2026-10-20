{
  lib,
  ...
}:

{
  virtualisation = {
    oci-containers.backend = "podman";
    podman = {
      enable = true;

      autoPrune = {
        enable = true;

        dates = "daily";
        flags = [
          "--all"
        ];
      };
      dockerCompat = true;
      dockerSocket.enable = true;
    };
  };
}
