{
  config,
  pkgs,
  ...
}:

{
  age.secrets = {
    gamevault-backend_environment = {
      file = ./gamevault/backend_environment.age;
      # mode = "600";
    };

    gamevault-db_environment = {
      file = ./gamevault/db_environment.age;
      # mode = "600";
    };
  };

  networking.firewall.allowedTCPPorts = [
    1337
  ];

  system.activationScripts = {
    create_gamevault_directories.text = ''
      mkdir -p /mnt/media/data/gamevault/db /mnt/media/games/windows && chown 1000:1000 -R /mnt/media/data/gamevault
    '';

    create_gamevault-network.text = ''
      ${pkgs.podman}/bin/podman network create gamevault-network --ignore
    '';
  };

  virtualisation.oci-containers.containers = {
    gamevault-backend = {
      image = "phalcode/gamevault-backend:latest";
      pull = "newer";
      hostname = "gamevault-backend";

      environmentFiles = [
        config.age.secrets.gamevault-backend_environment.path
      ];

      volumes = [
        "/mnt/media/data/gamevault:/media"
        "/mnt/media/games/windows:/files"
      ];

      ports = [
        "1337:8080/tcp"
      ];

      networks = [
        "gamevault-network"
      ];
    };

    gamevault-db = {
      image = "postgres:16";
      pull = "newer";
      hostname = "gamevault-db";
      user = "1000:1000";

      environmentFiles = [
        config.age.secrets.gamevault-db_environment.path
      ];

      volumes = [
        "/mnt/media/data/gamevault/db:/var/lib/postgresql/data"
      ];

      networks = [
        "gamevault-network"
      ];
    };
  };
}
