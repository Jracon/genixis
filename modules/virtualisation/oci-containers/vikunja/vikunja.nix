{
  ...
}:

{
  networking.firewall.allowedTCPPorts = [
    3456
  ];

  system.activationScripts.create_vikunja_directories.text = ''
    mkdir -p /mnt/vikunja/files /mnt/vikunja/db && chown -R 1000:1000 /mnt/vikunja
  '';

  virtualisation.oci-containers.containers = {
    vikunja = {
      image = "vikunja/vikunja:2.4.0";

      hostname = "vikunja";
      pull = "newer";

      ports = [
        "3456:3456"
      ];
      volumes = [
        "/mnt/vikunja/files:/app/vikunja/files"
        "/mnt/vikunja/db:/db"
      ];
    };
  };
}
