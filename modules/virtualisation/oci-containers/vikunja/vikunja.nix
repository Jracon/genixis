{
  config,
  ...
}:

{
  age.secrets = {
    vikunja_environment.file = ./environment.age;
  };

  networking.firewall.allowedTCPPorts = [
    3456
  ];

  system.activationScripts.create_vikunja_directories.text = ''
    mkdir -p /mnt/vikunja/files /mnt/vikunja/db && chown -R 1000:1000 /mnt/vikunja
  '';

  virtualisation.oci-containers.containers = {
    vikunja = {
      image = "docker.io/vikunja/vikunja";

      hostname = "vikunja";
      pull = "newer";

      environmentFiles = [
        config.age.secrets.vikunja_environment.path
      ];
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
