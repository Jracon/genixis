{
  config,
  ...
}:

{
  age.secrets = {
    monica_environment.file = ./environment.age;
    monica-db_environment.file = ./db_environment.age;
  };

  networking.firewall.allowedTCPPorts = [
    80
  ];

  system.activationScripts = {
    create_monica_directory.text = ''
      mkdir -p /mnt/monica/data
    '';

    create_monica_network.text = ''
      ${pkgs.podman}/bin/podman network create monica-network --ignore
    '';
  };

  virtualisation.oci-containers.containers = {
    monica = {
      image = "monica:apache";
      pull = "newer";
      hostname = "monica";

      dependsOn = [
        "monica-db"
      ];

      environmentFiles = [
        config.age.secrets.monica_environment.path
      ];

      networks = [
        "monica-network"
      ];

      ports = [
        "80:80"
      ];

      volumes = [
        "/mnt/monica/data:/var/www/html/storage"
      ];
    };

    monica-db = {
      image = "mariadb:11";
      pull = "newer";
      hostname = "monica-db";

      environmentFiles = [
        config.age.secrets.monica-db_environment.path
      ];

      networks = [
        "monica-network"
      ];

      volumes = [
        "/mnt/monica/mysqldata:/var/lib/mysql"
      ];
    };
  };
}