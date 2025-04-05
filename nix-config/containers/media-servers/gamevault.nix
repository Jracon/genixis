{
  config, 
  pkgs, 
  ...
}:

{
  age.secrets = {
    gamevault-backend_environment = {
      file = ./gamevault/backend_environment.age;
      mode = "600";
    };
    gamevault-db_environment = {
      file = ./gamevault/db_environment.age;
      mode = "600";
    };
  };

  networking.firewall = {
    allowedTCPPorts = [
      1337
    ];
  };

  system.activationScripts = {
    create_romm-network.text = ''
      ${pkgs.podman}/bin/podman network create gamevault-network
    '';
  };

  virtualisation.oci-containers.containers = {
    gamevault-backend = {
      hostname = "gamevault-backend";
      image = "phalcode/gamevault-backend:latest";

      environmentFiles = [
        config.age.secrets.gamevault-backend_environment.path
      ];
      extraOptions = [
        "--network=gamevault-network"
      ];
      ports = [
        "1337:8080/tcp"
      ];
      pull = "always";
      volumes = [
        "/mnt/media/data/gamevault:/media"
        "/mnt/media/games/windows:/files"
      ];
    };

    gamevault-db = {
      hostname = "gamevault-db";
      image = "postgres:16";

      environmentFiles = [
        config.age.secrets.gamevault-db_environment.path
      ];
      extraOptions = [
        "--network=gamevault-network"
      ];
      pull = "always";
      user = "1000:1000";
      volumes = [
        "/mnt/media/data/gamevault/db:/var/lib/postgresql/data"
      ];
    };
  };
}
