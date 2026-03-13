{
  config,
  pkgs,
  ...
}:

{
  age.secrets.tailscale_client_secret.file = ./client_secret.age;

  boot.initrd.systemd.network.wait-online.enable = false;

  environment.systemPackages = with pkgs; [
    ethtool
    networkd-dispatcher
  ];

  networking.firewall = {
    enable = true;

    allowedUDPPorts = [
      config.services.tailscale.port
    ];
    trustedInterfaces = [
      "tailscale0"
    ];
  };

  services = {
    networkd-dispatcher = {
      enable = true;

      rules."50-tailscale" = {
        onState = [
          "routable"
        ];
        script = ''
          NETDEV="$(ip -o route get 8.8.8.8 | cut -f 5 -d " ")"
          "${pkgs.ethtool}/sbin/ethtool" -K "$NETDEV" rx-udp-gro-forwarding on rx-gro-list off
        '';
      };
    };
    tailscale = {
      enable = true;

      authKeyFile = config.age.secrets.tailscale_client_secret.path;
      authKeyParameters.ephemeral = true;
      openFirewall = true;
      useRoutingFeatures = "server";

      extraUpFlags = [
        "--advertise-tags=tag:genixis"
        "--advertise-routes=10.0.0.0/24"
      ];
    };
  };

  systemd = {
    network.wait-online.enable = false;

    services.tailscaled.serviceConfig.Environment = [
      "TS_DEBUG_FIREWALL_MODE=nftables"
    ];
  };
}
