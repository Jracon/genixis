{
  config,
  pkgs,
  ...
}:

{
  age.secrets = {
    gamevault-backend_environment.file = ./gamevault/backend_environment.age;
    gamevault-db_environment.file = ./gamevault/db_environment.age;
  };

  networking.firewall.allowedTCPPorts = [
    1337
  ];

  system.activationScripts = {
    create_gamevault_directories.text = ''
      mkdir -p /mnt/gamevault/db /mnt/media/games/windows && chown 1000:1000 -R /mnt/gamevault
    '';
    create_gamevault-network.text = ''
      ${pkgs.podman}/bin/podman network create gamevault-network --ignore
    '';
  };

  virtualisation.oci-containers.containers = {
    gamevault-backend = {
      image = "phalcode/gamevault-backend:latest";

      hostname = "gamevault-backend";
      pull = "newer";

      environmentFiles = [
        config.age.secrets.gamevault-backend_environment.path
      ];
      networks = [
        "gamevault-network"
      ];
      ports = [
        "1337:8080/tcp"
      ];
      volumes = [
        "/mnt/gamevault:/media"
        "/mnt/media/games/windows:/files"
      ];
    };
    gamevault-db = {
      image = "postgres:16";

      hostname = "gamevault-db";
      pull = "newer";
      user = "1000:1000";

      environmentFiles = [
        config.age.secrets.gamevault-db_environment.path
      ];
      networks = [
        "gamevault-network"
      ];
      volumes = [
        "/mnt/gamevault/db:/var/lib/postgresql/data"
      ];
    };
  };
}
