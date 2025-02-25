{
  ...
}:

{
  virtualisation = {
    docker = {
      # autoPrune = {
      #   dates = "daily";
      #   enable = true;
      #   flags = ["--all"];
      # };

      enable = true;
      # enableOnBoot = true;

      # rootless = {
      #   enable = true;
      #   setSocketVariable = true;
      # };
      
      # storageDriver = "overlay2";
    };

    oci-containers = {
      backend = "docker";
    };
  };
}