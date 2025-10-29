{
  config,
  ...
}:

{
  # age.secrets.mealie_environment = {
  #   file = ./environment.age;
  #   # mode = "600";
  # };

  networking.firewall.allowedTCPPorts = [
    9925
  ];

  system.activationScripts.create_mealie_directory.text = ''
    mkdir -p /mnt/mealie
  '';

  virtualisation.oci-containers.containers.mealie = {
    image = "ghcr.io/mealie-recipes/mealie:v2.8.0";
    pull = "always";
    hostname = "caddy";

    environmentFiles = [
      config.age.secrets.mealie_environment.path
    ];

    volumes = [
      "/mnt/mealie:/app/data"
    ];

    ports = [
      "9925:9000"
    ];
  };
}
