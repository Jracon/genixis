{
  ...
}:

{
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

    volumes = [
      "/mnt/radicale/config:/etc/radicale"
      "/mnt/radicale/data:/var/lib/radicale"
    ];
  };
}
