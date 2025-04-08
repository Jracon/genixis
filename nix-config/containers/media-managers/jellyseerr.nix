{
  ...
}:

{
  networking.firewall = {
    allowedTCPPorts = [
      5055
    ];
  };

  system.activationScripts = {
    create_jellyseerr_directory.text = ''
      mkdir -p /mnt/media/data/jellyseerr
    '';
  };

  virtualisation.oci-containers.containers = {
    jellyseerr = {
      hostname = "jellyseerr";
      image = "ghcr.io/fallenbagel/jellyseerr:latest";

      environment = {
        TZ = "America/Phoenix";
      };
      ports = [
        "5055:5055"
      ];
      pull = "always";
      volumes = [
        "/mnt/media/data/jellyseerr:/app/config"
      ];
    };
  };
}
