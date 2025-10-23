{
  ...
}:

{
  virtualisation = {
    oci-containers.backend = "docker";

    docker = {
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
