{
  environment.sessionVariables = {
    DOCKER_HOST = "unix:///run/podman/podman.sock";
  };

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
