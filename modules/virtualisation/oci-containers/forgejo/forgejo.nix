{
  config,
  pkgs,
  ...
}:

{
  age.secrets.genixis_runner_token.file = ./genixis_runner_token.age;

  networking.firewall.allowedTCPPorts = [
    222
    4000
  ];

  services.forgejo-runner.instances.genixis_flake_update_runner = {
    enable = true;

    # Jobs run directly on the host (the "native" label), so builds go through the
    # host's sandboxed nix-daemon, and the runner needs no Podman access.
    hostPackages = [
      config.nix.package
      pkgs.bash
      pkgs.coreutils
      pkgs.curl
      pkgs.gawk
      pkgs.git
      pkgs.gnused
      pkgs.nodejs
      pkgs.wget
    ];
    secrets.server.connections.default.token_url = config.age.secrets.genixis_runner_token.path;
    settings = {
      runner.labels = [
        "native:host"
      ];
      server.connections.default = {
        url = "https://forgejo.local.jracon.xyz";
        uuid = "382455b1-b41d-4a71-8104-66c5136e90ab";
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
