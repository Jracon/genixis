{
  networking.firewall = {
    allowedTCPPorts = [
      8084
    ];
    allowedUDPPorts = [
      8084
    ];
  };

  system.activationScripts.create_shelfmark_directories.text = ''
    mkdir -p /mnt/media/downloads/shelfmark /mnt/shelfmark/config
  '';

  virtualisation.oci-containers.containers = {
    shelfmark = {
      image = "ghcr.io/calibrain/shelfmark:latest";

      hostname = "shelfmark";
      pull = "newer";

      environment = {
        FLASK_PORT = "8084";
        TZ = "America/Phoenix";
      };
      ports = [
        "8084:8084"
      ];
      volumes = [
        "/mnt/media/downloads/shelfmark:/books"
        "/mnt/shelfmark/config:/config"
      ];
    };
  };
}
