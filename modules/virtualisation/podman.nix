{
  virtualisation = {
    oci-containers.backend = "podman";

    podman = {
      enable = true;

      dockerCompat = true;
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
