{
  virtualisation = {
    oci-containers.backend = "podman";

    podman = {
      enable = true;

      dockerCopmat = true;
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
