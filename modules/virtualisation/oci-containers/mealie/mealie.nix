{
  config,
  ...
}:

{
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
      "/run/credentials/@system/mealie_environment"
    ];

    volumes = [
      "/mnt/mealie:/app/data"
    ];

    ports = [
      "9925:9000"
    ];
  };
}
