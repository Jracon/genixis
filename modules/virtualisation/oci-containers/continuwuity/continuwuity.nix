{
  networking.firewall.allowedTCPPorts = [
    8008
  ];

  system.activationScripts.create_continuwuity_directory.text = ''
    mkdir -p /mnt/continuwuity
  '';

  virtualisation.oci-containers.containers.continuwuity = {
    image = "forgejo.ellis.link/continuwuation/continuwuity:latest";

    hostname = "continuwuity";
    pull = "newer";

    environment = {
      CONTINUWUITY_ADDRESS = "0.0.0.0";
      CONTINUWUITY_DATABASE_PATH = "/var/lib/continuwuity";
      CONTINUWUITY_PORT = "8008";
      CONTINUWUITY_SERVER_NAME = "jracon.xyz";
    };
    ports = [
      "8008:8008"
    ];
    volumes = [
      "db:/var/lib/continuwuity"
    ];
  };
}
