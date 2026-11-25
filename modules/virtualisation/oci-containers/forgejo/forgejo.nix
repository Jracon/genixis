{
  config,
  pkgs,
  ...
}:
let
  # the shared shapes of the container modules (lib/oci-containers.nix)
  oci = import ../../../../lib/oci-containers.nix;
in
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
      pkgs.python3
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

  # Hide this host's machine config from CI, so --impure evaluation of every host
  # falls back to common/dummy-configuration.nix instead of loading services' own.
  systemd.services.forgejo-runner-genixis_flake_update_runner.serviceConfig.TemporaryFileSystem = [
    "/etc/nixos:ro"
  ];

  virtualisation.oci-containers.containers.forgejo = {
    image = "codeberg.org/forgejo/forgejo:17.0.1";

    hostname = "forgejo";
    pull = "newer";

    environment = {
      # Caddy reaches Forgejo from Podman's default network; trust its X-Forwarded-For
      # (v16 dropped the container image's default of "*")
      FORGEJO__security__REVERSE_PROXY_TRUSTED_PROXIES = "127.0.0.0/8,::1/128,10.88.0.0/16";
      # the dispatcher receiver binds the gateway of the Podman default bridge
      # (10.88.0.1), a private address that the webhook SSRF guard denies by
      # default; allow exactly that host beside the default external targets
      FORGEJO__webhook__ALLOWED_HOST_LIST = "external,10.88.0.1";
      TZ = config.time.timeZone;
      USER_GID = "1000";
      USER_UID = "1000";
    };
    # the static address of the container on the default bridge: the allow
    # list of a leg unit of the sandbox tier names this address, because
    # the ssh publish below is a DNAT rule that rewrites the destination of
    # a connect to the container, and the egress filter of a leg reads the
    # destination after the rewrite (lib/oci-containers.nix,
    # forgeContainerAddress)
    extraOptions = [ "--ip=${oci.forgeContainerAddress}" ];
    ports = [
      "222:22"
      "4000:3000"
    ];
    volumes = [
      "/mnt/forgejo/data:/data"
    ];
  };
}
