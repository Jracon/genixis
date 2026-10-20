{
  config,
  ...
}:

{
  age.secrets.genixis_registration_token.file = ./genixis_registration_token.age;

  networking.firewall.allowedTCPPorts = [
    222
    4000
  ];

  services.forgejo-runner.instances.genixis_flake_update_runner = {
    enable = true;

    secrets.server.connections.default.token_url = config.age.secrets.genixis_registration_token.path;
    settings = {
      runner.labels = [
        "ubuntu-latest:docker://ghcr.io/catthehacker/ubuntu:act-22.04"
      ];
      server.connections.default = {
        url = "https://forgejo.local.jracon.xyz";
        uuid = "cd6acaf3-efd5-4df3-9922-f357e08d65a0";
      };
    };
  };

  system.activationScripts.create_forgejo_directory.text = ''
    mkdir -p /mnt/forgejo/data
  '';

  virtualisation.oci-containers.containers.forgejo = {
    image = "codeberg.org/forgejo/forgejo:14";

    hostname = "forgejo";
    pull = "newer";

    environment = {
      USER_GID = "1000";
      USER_UID = "1000";
    };
    ports = [
      "222:22"
      "4000:3000"
    ];
    volumes = [
      "/mnt/forgejo/data:/data"
    ];
  };
}
