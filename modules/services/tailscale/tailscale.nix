{
  config,
  lib,
  pkgs,
  ...
}:

{
  age.secrets.tailscale_client_secret.file = ./client_secret.age;

  environment.systemPackages = with pkgs; [
    ethtool
    networkd-dispatcher
  ];

  services = {
    networkd-dispatcher = {
      enable = true;

      rules."50-tailscale" = {
        onState = [
          "routable"
        ];
        script = ''
          NETDEV=$(ip -o route get 8.8.8.8 | cut -f 5 -d " ")
          echo "$NETDEV"
          ${lib.getExe ethtool} -K "$NETDEV" rx-udp-gro-forwarding on rx-gro-list off
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
}
