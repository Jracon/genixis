{
  config,
  ...
}:

{
  age.secrets = {
    radicale_config = {
      file = ./config.age;
      group = "1000";
      owner = "1000";
    };
    radicale_users = {
      file = ./users.age;
      group = "1000";
      owner = "1000";
    };
  };

  networking.firewall.allowedTCPPorts = [
    5232
  ];

  system.activationScripts.create_radicale_directories = ''
    mkdir -p /mnt/radicale/config /mnt/radicale/data
  '';

  virtualisation.oci-containers.containers.radicale = {
    image = "ghcr.io/kozea/radicale:stable";

    hostname = "radicale";
    pull = "newer";

    ports = [
      "5232:5232"
    ];
    volumes = [
      "/mnt/radicale/config:/etc/radicale"
      "${config.age.secrets.radicale_config.path}:/etc/radicale/config"
      "${config.age.secrets.radicale_users.path}:/etc/radicale/users"
      "/mnt/radicale/data:/var/lib/radicale"
    ];
  };
}
