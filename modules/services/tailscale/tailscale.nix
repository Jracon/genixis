{
  config,
  ...
}:

{
  age.secrets.tailscale_client_secret.file = ./client_secret.age;

  services.tailscale = {
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
