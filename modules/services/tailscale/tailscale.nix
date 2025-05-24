{
  config, 
  pkgs, 
  ...
}:

{
  age.secrets.tailscale_client_secret.file = ./client_secret.age;

  services.tailscale = {
    authKeyFile = config.age.secrets.tailscale_client_secret.path;
    authKeyParameters.ephemeral = true;
    enable = true;
    openFirewall = true;
    useRoutingFeatures = "server";

    extraUpFlags = [
      "--advertise-tags=tag:genixis"
    ];
  };

  systemd = {
    network.wait-online.enable = true;

    services.tailscaled-autoconnect = {
      after = [
        "network-online.target"
        "systemd-resolved.service"
      ];

      wants = [
        "network-online.target"
      ];
    };
  };
}
