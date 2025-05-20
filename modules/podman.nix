{
  ...
}:

{
  # enable Podman with autoPrune, and set the default container backend
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
    };
  };
}
