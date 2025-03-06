{
  ...
}:

{
  virtualisation = {
    podman = {
      autoPrune = {
        dates = "daily";
        enable = true;
        flags = ["--all"];
      };

      enable = true;
    };

    oci-containers = {
      backend = "podman";
    };
  };
}