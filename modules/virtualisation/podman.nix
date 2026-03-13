{
  virtualisation = {
    oci-containers.backend = "podman";

    podman = {
      enable = true;

      dockerSocket.enable = true;

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
