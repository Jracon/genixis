{
  config, 
  ...
}:

{
  age.secrets.vaultwarden_environment = {
    file = ./environment.age;
    mode = "600";
  };

  networking.firewall = {
    allowedTCPPorts = [
      80
    ];
  };

  virtualisation.oci-containers.containers = {
    vaultwarden = {
      hostname = "vaultwarden";
      image = "vaultwarden/server:latest";

      environmentFiles = [
        config.age.secrets.vaultwarden_environment.path
      ];
      ports = [
        "80:80"
      ];
      pull = "always";
      volumes = [
        "/mnt/vaultwarden:/data"
      ];
    };
  };
}
